import type { Env } from "./env";

const MIN_ACTIVITY_WINDOW_MS = 6 * 60 * 60 * 1_000;
const MAX_ACTIVITY_WINDOW_MS = 7 * 24 * 60 * 60 * 1_000;
const MIN_PAYMENTS_FOR_CADENCE = 3;

type SourceStatus = "setup" | "active" | "paused";
type EventStatus = "received" | "accepted" | "duplicate" | "rejected" | "ignored" | null;

export interface CustomSourceHealthInput {
  status: SourceStatus;
  lastEventReceivedAt: string | null;
  lastEventStatus: EventStatus;
  lastEventError: string | null;
  lastPaymentReceivedAt: string | null;
  recentPaymentTimes: string[];
  now?: Date;
}

export type CustomSourceHealthStatus = "awaiting_events" | "receiving" | "needs_attention" | "paused";

export interface CustomSourceHealth {
  status: CustomSourceHealthStatus;
  reason: "rejected" | "quiet" | null;
  lastEventReceivedAt: string | null;
  lastPaymentReceivedAt: string | null;
  expectedEventBy: string | null;
  detail: string;
}

function timestamp(value: string): number {
  const normalized = value.includes("T") ? value : `${value.replace(" ", "T")}Z`;
  return Date.parse(normalized);
}

function median(values: number[]): number {
  const ordered = [...values].sort((left, right) => left - right);
  const middle = Math.floor(ordered.length / 2);
  return ordered.length % 2 === 0
    ? (ordered[middle - 1] + ordered[middle]) / 2
    : ordered[middle];
}

function activityWindow(paymentTimes: string[]): number | null {
  if (paymentTimes.length < MIN_PAYMENTS_FOR_CADENCE) return null;
  const times = paymentTimes.map(timestamp).filter(Number.isFinite).sort((left, right) => right - left);
  if (times.length < MIN_PAYMENTS_FOR_CADENCE) return null;
  const intervals = times.slice(0, -1).map((time, index) => time - times[index + 1]);
  const adaptive = median(intervals) * 3;
  return Math.min(MAX_ACTIVITY_WINDOW_MS, Math.max(MIN_ACTIVITY_WINDOW_MS, adaptive));
}

export function classifyCustomSourceHealth(input: CustomSourceHealthInput): CustomSourceHealth {
  const base = {
    lastEventReceivedAt: input.lastEventReceivedAt,
    lastPaymentReceivedAt: input.lastPaymentReceivedAt,
  };
  if (input.status === "paused") {
    return {
      status: "paused",
      reason: null,
      ...base,
      expectedEventBy: null,
      detail: "Monitoring is paused while payment intake is paused.",
    };
  }
  if (!input.lastEventReceivedAt) {
    return {
      status: "awaiting_events",
      reason: null,
      ...base,
      expectedEventBy: null,
      detail: "No webhook event has been received yet.",
    };
  }
  if (input.lastEventStatus === "rejected") {
    return {
      status: "needs_attention",
      reason: "rejected",
      ...base,
      expectedEventBy: null,
      detail: input.lastEventError ?? "The latest webhook event could not be accepted.",
    };
  }

  const window = input.status === "active" ? activityWindow(input.recentPaymentTimes) : null;
  const lastEvent = timestamp(input.lastEventReceivedAt);
  const expectedEventBy = window && Number.isFinite(lastEvent)
    ? new Date(lastEvent + window).toISOString()
    : null;
  if (expectedEventBy && (input.now ?? new Date()).getTime() > Date.parse(expectedEventBy)) {
    return {
      status: "needs_attention",
      reason: "quiet",
      ...base,
      expectedEventBy,
      detail: "No webhook requests arrived within this source's expected activity window. This does not prove the sender is disconnected; check it if you expected payments.",
    };
  }
  return {
    status: "receiving",
    reason: null,
    ...base,
    expectedEventBy,
    detail: "Cha-Ching received a webhook event.",
  };
}

interface MonitorSourceRow {
  id: string;
  user_id: string;
  name: string;
  status: "active";
  last_event_received_at: string | null;
  last_event_status: EventStatus;
  last_event_error: string | null;
  last_payment_received_at: string | null;
  health_alerted_at: string | null;
}

export async function monitorCustomSourceHealth(env: Env, now = new Date()): Promise<void> {
  const sources = await env.DB.prepare(
    `SELECT id, user_id, name, status, last_event_received_at, last_event_status,
            last_event_error, last_payment_received_at, health_alerted_at
     FROM custom_payment_sources WHERE status = 'active'`,
  ).all<MonitorSourceRow>();

  for (const source of sources.results) {
    const payments = await env.DB.prepare(
      `SELECT created_at FROM sales WHERE provider = 'custom' AND provider_account_id = ?1
       ORDER BY created_at DESC LIMIT 10`,
    ).bind(source.id).all<{ created_at: string }>();
    const health = classifyCustomSourceHealth({
      status: source.status,
      lastEventReceivedAt: source.last_event_received_at,
      lastEventStatus: source.last_event_status,
      lastEventError: source.last_event_error,
      lastPaymentReceivedAt: source.last_payment_received_at,
      recentPaymentTimes: payments.results.map((payment) => payment.created_at),
      now,
    });
    if (health.status !== "needs_attention" || source.health_alerted_at) continue;

    await env.NOTIFICATION_QUEUE.send({
      connectionHealth: {
        userId: source.user_id,
        sourceId: source.id,
        sourceName: source.name,
        body: health.reason === "rejected"
          ? `${health.detail} Open Cha-Ching to review the connection.`
          : "No webhook requests arrived within this source's expected activity window. Open Cha-Ching to review the connection.",
      },
    });
    await env.DB.prepare(
      "UPDATE custom_payment_sources SET health_alerted_at = CURRENT_TIMESTAMP WHERE id = ?1 AND health_alerted_at IS NULL",
    ).bind(source.id).run();
  }
}
