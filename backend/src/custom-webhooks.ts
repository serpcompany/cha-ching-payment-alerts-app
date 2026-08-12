import type { Auth } from "./auth";
import { requireUser } from "./auth";
import { decryptSecret, encryptSecret, randomToken, sha256 } from "./crypto";
import { requireCustomSourceEntitlement } from "./entitlements";
import type { Env } from "./env";
import { classifyCustomSourceHealth } from "./custom-source-health";
import { enqueueSaleNotification } from "./notification-queue";
import { formatMinorAmount, notificationFieldsBody, sendTestNotification } from "./notifications";
import type { TestNotificationMessage } from "./notifications";

export interface DiscoveredWebhookField {
  path: string;
  value: string | number | boolean;
  valueType: "string" | "number" | "boolean";
}

export interface WebhookFieldMapping {
  paymentIdPath: string;
  amountPath: string;
  amountUnit: "major" | "minor";
  currencyPath?: string;
  fixedCurrency?: string;
  occurredAtPath?: string;
  productPath?: string;
  planPath?: string;
  saleTypePath?: string;
  notificationFields?: NotificationFieldMapping[];
}

export interface NotificationFieldMapping {
  id: string;
  path: string;
  label: string;
  enabled: boolean;
}

export interface NotificationFieldPreview extends NotificationFieldMapping {
  value: string;
}

export interface NormalizedCustomPayment {
  paymentId: string;
  amountMinor: number;
  currency: string;
  occurredAt: number;
  productLabel: string;
  isSubscription: boolean;
  details: {
    plan: string | null;
    saleType: string | null;
  };
}

interface CustomSourceRow {
  id: string;
  name: string;
  status: "setup" | "active" | "paused";
  webhook_token_ciphertext: string;
  sample_payload_ciphertext?: string | null;
  sample_received_at?: string | null;
  sample_error?: string | null;
  mapping_json?: string | null;
  last_event_received_at?: string | null;
  last_event_status?: "received" | "accepted" | "duplicate" | "rejected" | "ignored" | null;
  last_event_error?: string | null;
  last_payment_received_at?: string | null;
  created_at: string;
  updated_at: string;
}

interface HistoricalNotificationFieldsRow {
  id: string;
  notification_fields_json: string;
  notification_field_values_json: string | null;
}

type CustomSourceConnectionState = "waiting" | "event_received" | "active" | "paused";

const MAX_CUSTOM_WEBHOOK_BYTES = 64 * 1024;

function webhookURL(env: Env, token: string): string {
  const base = new URL(env.PUBLIC_BASE_URL);
  base.pathname = `/v1/webhooks/custom/${encodeURIComponent(token)}`;
  base.search = "";
  base.hash = "";
  return base.toString();
}

async function publicSource(env: Env, row: CustomSourceRow) {
  const token = await decryptSecret(row.webhook_token_ciphertext, env.PROVIDER_TOKEN_ENCRYPTION_KEY);
  const recentPayments = row.status === "active"
    ? await env.DB.prepare(
      `SELECT created_at FROM sales WHERE provider = 'custom' AND provider_account_id = ?1
       ORDER BY created_at DESC LIMIT 10`,
    ).bind(row.id).all<{ created_at: string }>()
    : { results: [] as Array<{ created_at: string }> };
  return {
    id: row.id,
    name: row.name,
    status: row.status,
    connectionState: sourceConnectionState(row),
    health: classifyCustomSourceHealth({
      status: row.status,
      lastEventReceivedAt: row.last_event_received_at ?? null,
      lastEventStatus: row.last_event_status ?? null,
      lastEventError: row.last_event_error ?? null,
      lastPaymentReceivedAt: row.last_payment_received_at ?? null,
      recentPaymentTimes: recentPayments.results.map((payment) => payment.created_at),
    }),
    webhookUrl: webhookURL(env, token),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function sourceConnectionState(row: CustomSourceRow): CustomSourceConnectionState {
  if (row.status === "active" || row.status === "paused") return row.status;
  return row.sample_received_at ? "event_received" : "waiting";
}

async function createSource(env: Env, auth: Auth, request: Request): Promise<Response> {
  const user = await requireUser(auth, request);
  await requireCustomSourceEntitlement(env.DB, user.id);
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: "Invalid JSON" }, { status: 400 });
  }
  const name = typeof (body as { name?: unknown })?.name === "string"
    ? (body as { name: string }).name.trim()
    : "";
  if (!name || name.length > 80) {
    return Response.json({ error: "Name must be between 1 and 80 characters" }, { status: 400 });
  }
  const id = crypto.randomUUID();
  const token = randomToken();
  const [tokenHash, tokenCiphertext] = await Promise.all([
    sha256(token),
    encryptSecret(token, env.PROVIDER_TOKEN_ENCRYPTION_KEY),
  ]);
  await env.DB.prepare(
    `INSERT INTO custom_payment_sources (
      id, user_id, name, status, webhook_token_hash, webhook_token_ciphertext
    ) VALUES (?1, ?2, ?3, 'setup', ?4, ?5)`,
  ).bind(id, user.id, name, tokenHash, tokenCiphertext).run();
  const row = await env.DB.prepare(
    `SELECT id, name, status, webhook_token_ciphertext, sample_received_at,
            last_event_received_at, last_event_status, last_event_error,
            last_payment_received_at, created_at, updated_at
     FROM custom_payment_sources WHERE id = ?1 AND user_id = ?2`,
  ).bind(id, user.id).first<CustomSourceRow>();
  return Response.json({ source: await publicSource(env, row!) }, { status: 201 });
}

async function listSources(env: Env, auth: Auth, request: Request): Promise<Response> {
  const user = await requireUser(auth, request);
  const result = await env.DB.prepare(
    `SELECT id, name, status, webhook_token_ciphertext, sample_received_at,
            last_event_received_at, last_event_status, last_event_error,
            last_payment_received_at, created_at, updated_at
     FROM custom_payment_sources WHERE user_id = ?1 ORDER BY created_at, id`,
  ).bind(user.id).all<CustomSourceRow>();
  return Response.json({ sources: await Promise.all(result.results.map((row) => publicSource(env, row))) });
}

function suggestedMapping(fields: DiscoveredWebhookField[]): Partial<WebhookFieldMapping> {
  const find = (...patterns: RegExp[]) => fields.find((field) => patterns.some((pattern) => pattern.test(field.path)))?.path;
  return {
    paymentIdPath: find(/\/(payment|order|transaction|event)[_-]?id$/i, /\/id$/i),
    amountPath: find(/\/(amount|total|price|value)(?:[_-]?(minor|cents))?$/i),
    currencyPath: find(/\/currency(?:[_-]?code)?$/i),
    occurredAtPath: find(/\/(occurred|created|paid)[_-]?at$/i, /\/timestamp$/i),
    productPath: find(/\/(product|item)(?:[_-]?name)?$/i),
    planPath: find(/\/plan(?:[_-]?name)?$/i),
    saleTypePath: find(/\/(sale|payment|event)[_-]?type$/i, /\/type$/i),
  };
}

async function getSource(env: Env, auth: Auth, request: Request, sourceId: string): Promise<Response> {
  const user = await requireUser(auth, request);
  const row = await env.DB.prepare(
    `SELECT id, name, status, webhook_token_ciphertext, sample_payload_ciphertext,
            sample_received_at, sample_error, mapping_json, last_event_received_at,
            last_event_status, last_event_error, last_payment_received_at,
            created_at, updated_at
     FROM custom_payment_sources WHERE id = ?1 AND user_id = ?2`,
  ).bind(sourceId, user.id).first<CustomSourceRow>();
  if (!row) return Response.json({ error: "Payment source not found" }, { status: 404 });
  let sample: unknown = null;
  if (row.sample_payload_ciphertext && row.sample_received_at) {
    const payload = JSON.parse(await decryptSecret(
      row.sample_payload_ciphertext,
      env.PROVIDER_TOKEN_ENCRYPTION_KEY,
    ));
    const fields = flattenWebhookPayload(payload);
    sample = {
      receivedAt: row.sample_received_at,
      fields,
      suggestions: suggestedMapping(fields),
    };
  } else if (row.sample_error) {
    sample = { error: row.sample_error };
  }
  return Response.json({
    source: await publicSource(env, row),
    sample,
    ...(row.mapping_json ? { mapping: JSON.parse(row.mapping_json) } : {}),
  });
}

function parseMapping(value: unknown): WebhookFieldMapping | null {
  if (!value || typeof value !== "object") return null;
  const item = value as Record<string, unknown>;
  if (typeof item.paymentIdPath !== "string" || typeof item.amountPath !== "string") return null;
  if (item.amountUnit !== "major" && item.amountUnit !== "minor") return null;
  const optionalPaths = ["currencyPath", "fixedCurrency", "occurredAtPath", "productPath", "planPath", "saleTypePath"];
  if (optionalPaths.some((key) => item[key] !== undefined && typeof item[key] !== "string")) return null;
  if (!item.currencyPath && !item.fixedCurrency) return null;
  let notificationFields: NotificationFieldMapping[] | undefined;
  if (item.notificationFields !== undefined) {
    if (!Array.isArray(item.notificationFields)) return null;
    notificationFields = [];
    const ids = new Set<string>();
    for (const rawField of item.notificationFields) {
      if (!rawField || typeof rawField !== "object") return null;
      const field = rawField as Record<string, unknown>;
      const id = typeof field.id === "string" ? field.id.trim() : "";
      const path = typeof field.path === "string" ? field.path.trim() : "";
      const label = typeof field.label === "string" ? field.label.trim() : "";
      if (!id || id.length > 500 || ids.has(id)) return null;
      if (!path.startsWith("/") || path.length > 500) return null;
      if (typeof field.enabled !== "boolean" || label.length > 50 || (field.enabled && !label)) return null;
      ids.add(id);
      notificationFields.push({ id, path, label, enabled: field.enabled });
    }
  }
  return {
    ...(item as unknown as WebhookFieldMapping),
    ...(notificationFields ? { notificationFields } : {}),
  };
}

function serializedMapping(mapping: WebhookFieldMapping): string {
  return JSON.stringify({
    paymentIdPath: mapping.paymentIdPath,
    amountPath: mapping.amountPath,
    amountUnit: mapping.amountUnit,
    ...(mapping.currencyPath ? { currencyPath: mapping.currencyPath } : {}),
    ...(mapping.fixedCurrency ? { fixedCurrency: mapping.fixedCurrency } : {}),
    ...(mapping.occurredAtPath ? { occurredAtPath: mapping.occurredAtPath } : {}),
    ...(mapping.productPath ? { productPath: mapping.productPath } : {}),
    ...(mapping.planPath ? { planPath: mapping.planPath } : {}),
    ...(mapping.saleTypePath ? { saleTypePath: mapping.saleTypePath } : {}),
    ...(mapping.notificationFields ? { notificationFields: mapping.notificationFields } : {}),
  });
}

async function updateNotificationFields(
  env: Env,
  auth: Auth,
  request: Request,
  sourceId: string,
): Promise<Response> {
  const user = await requireUser(auth, request);
  const row = await env.DB.prepare(
    `SELECT mapping_json FROM custom_payment_sources
     WHERE id = ?1 AND user_id = ?2 AND status IN ('active', 'paused')`,
  ).bind(sourceId, user.id).first<{ mapping_json: string | null }>();
  if (!row?.mapping_json) return Response.json({ error: "Active payment source not found" }, { status: 404 });

  let input: unknown;
  try {
    input = await request.json();
  } catch {
    return Response.json({ error: "Invalid JSON" }, { status: 400 });
  }
  const current = parseMapping(JSON.parse(row.mapping_json));
  const requestedFields = (input as { notificationFields?: unknown })?.notificationFields;
  const updated = current && parseMapping({ ...current, notificationFields: requestedFields });
  if (!current || !updated?.notificationFields) {
    return Response.json({ error: "Invalid notification fields" }, { status: 400 });
  }
  const currentPaths = new Map((current.notificationFields ?? []).map((field) => [field.id, field.path]));
  const changesPresentationOnly = updated.notificationFields.length === currentPaths.size
    && updated.notificationFields.every((field) => currentPaths.get(field.id) === field.path);
  if (!changesPresentationOnly) {
    return Response.json({ error: "Active notification fields can only be renamed, shown, hidden, or reordered" }, { status: 400 });
  }

  const mappingJSON = serializedMapping(updated);
  const history = await env.DB.prepare(
    `SELECT id, notification_fields_json, notification_field_values_json FROM sales
     WHERE provider = 'custom' AND provider_account_id = ?1 AND user_id = ?2
       AND notification_fields_json IS NOT NULL`,
  ).bind(sourceId, user.id).all<HistoricalNotificationFieldsRow>();
  const statements = [
    env.DB.prepare(
      "UPDATE custom_payment_sources SET mapping_json = ?1, updated_at = CURRENT_TIMESTAMP WHERE id = ?2 AND user_id = ?3",
    ).bind(mappingJSON, sourceId, user.id),
    ...history.results.flatMap((sale) => {
      const fields = applyHistoricalNotificationPresentation(
        sale.notification_fields_json,
        sale.notification_field_values_json,
        current.notificationFields ?? [],
        updated.notificationFields ?? [],
      );
      return fields === null ? [] : [env.DB.prepare(
        `UPDATE sales SET notification_fields_json = ?1, notification_field_values_json = ?2
         WHERE id = ?3 AND user_id = ?4`,
      ).bind(fields.presentation, fields.archive, sale.id, user.id)];
    }),
  ];
  await env.DB.batch(statements);
  return Response.json({ mapping: JSON.parse(mappingJSON) });
}

function applyHistoricalNotificationPresentation(
  value: string,
  archivedValue: string | null,
  current: NotificationFieldMapping[],
  updated: NotificationFieldMapping[],
): { presentation: string; archive: string } | null {
  let stored: Array<{ label: string; value: string }>;
  try {
    const parsed = JSON.parse(value) as unknown;
    if (!Array.isArray(parsed)) return null;
    stored = parsed.filter((field): field is { label: string; value: string } => Boolean(
      field && typeof field === "object"
      && typeof (field as Record<string, unknown>).label === "string"
      && typeof (field as Record<string, unknown>).value === "string"
    ));
    if (stored.length !== parsed.length) return null;
  } catch {
    return null;
  }

  const valuesById = new Map<string, string>();
  if (archivedValue) {
    try {
      const archived = JSON.parse(archivedValue) as unknown;
      if (!Array.isArray(archived)) return null;
      for (const field of archived) {
        if (!field || typeof field !== "object") return null;
        const id = (field as Record<string, unknown>).id;
        const fieldValue = (field as Record<string, unknown>).value;
        if (typeof id !== "string" || typeof fieldValue !== "string") return null;
        valuesById.set(id, fieldValue);
      }
    } catch {
      return null;
    }
  } else {
    const availableByLabel = new Map<string, NotificationFieldMapping[]>();
    for (const field of current) {
      const matches = availableByLabel.get(field.label) ?? [];
      matches.push(field);
      availableByLabel.set(field.label, matches);
    }
    for (const field of stored) {
      const matches = availableByLabel.get(field.label);
      const mapped = matches?.shift();
      if (mapped) valuesById.set(mapped.id, field.value);
    }
  }
  if (stored.length > 0 && valuesById.size === 0) return null;
  const presentation = JSON.stringify(updated.flatMap((field) => {
    const fieldValue = valuesById.get(field.id);
    return field.enabled && fieldValue !== undefined ? [{ label: field.label, value: fieldValue }] : [];
  }));
  const archive = JSON.stringify(Array.from(valuesById, ([id, fieldValue]) => ({ id, value: fieldValue })));
  return { presentation, archive };
}

function notificationFieldValue(
  payload: unknown,
  field: NotificationFieldMapping,
  mapping: WebhookFieldMapping,
  normalized: NormalizedCustomPayment,
): string | null {
  if (field.path === mapping.amountPath) {
    return formatMinorAmount(normalized.amountMinor, normalized.currency);
  }
  if (field.path === mapping.currencyPath) return normalized.currency;
  if (field.path === mapping.occurredAtPath) {
    return new Date(normalized.occurredAt * 1_000).toISOString();
  }
  const value = valueAtPointer(payload, field.path);
  if (typeof value !== "string" && typeof value !== "number" && typeof value !== "boolean") {
    return null;
  }
  const displayValue = String(value).trim().slice(0, 200);
  const fieldName = decodedPointerSegment(field.path.split("/").at(-1) ?? "").toLowerCase();
  if (typeof value === "string" && ["purchase_type", "sale_event"].includes(fieldName)) {
    const words = displayValue.replace(/[_-]+/g, " ").trim().toLowerCase();
    return words ? words[0].toUpperCase() + words.slice(1) : words;
  }
  return displayValue;
}

function previewNotificationFields(
  payload: unknown,
  mapping: WebhookFieldMapping,
  normalized: NormalizedCustomPayment,
  omitMissing = false,
): NotificationFieldPreview[] {
  const fields = (mapping.notificationFields ?? []).flatMap((field): NotificationFieldPreview[] => {
    const value = notificationFieldValue(payload, field, mapping, normalized);
    if (value !== null) return [{ ...field, value }];
    if (omitMissing) return [];
    if (field.enabled) throw new Error(`Notification field ${field.label} is missing`);
    return [{ ...field, value: "" }];
  });
  const body = notificationFieldsBody(fields.filter((field) => field.enabled)) || "Payment received.";
  if (new TextEncoder().encode(body).byteLength > 3_000) {
    throw new Error("Notification is too long. Turn off some fields or shorten their display names.");
  }
  return fields;
}

async function saveMapping(env: Env, auth: Auth, request: Request, sourceId: string): Promise<Response> {
  const user = await requireUser(auth, request);
  let mapping: WebhookFieldMapping | null = null;
  try {
    mapping = parseMapping(await request.json());
  } catch {
    // The response below intentionally does not distinguish malformed JSON.
  }
  if (!mapping) return Response.json({ error: "Invalid field mapping" }, { status: 400 });
  const row = await env.DB.prepare(
    `SELECT name, sample_payload_ciphertext FROM custom_payment_sources
     WHERE id = ?1 AND user_id = ?2 AND status = 'setup'`,
  ).bind(sourceId, user.id).first<{ name: string; sample_payload_ciphertext: string | null }>();
  if (!row) return Response.json({ error: "Payment source not found or already active" }, { status: 404 });
  if (!row.sample_payload_ciphertext) {
    return Response.json({ error: "Send a sample payment before mapping fields" }, { status: 409 });
  }
  const payload = JSON.parse(await decryptSecret(
    row.sample_payload_ciphertext,
    env.PROVIDER_TOKEN_ENCRYPTION_KEY,
  ));
  let normalized: NormalizedCustomPayment;
  try {
    normalized = normalizeCustomPayment(payload, mapping, row.name);
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Invalid field mapping" }, { status: 422 });
  }
  let notificationFields: NotificationFieldPreview[] | undefined;
  try {
    notificationFields = mapping.notificationFields
      ? previewNotificationFields(payload, mapping, normalized)
      : undefined;
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Invalid notification fields" }, { status: 422 });
  }
  await env.DB.prepare(
    "UPDATE custom_payment_sources SET mapping_json = ?1, sample_error = NULL, updated_at = CURRENT_TIMESTAMP WHERE id = ?2 AND user_id = ?3",
  ).bind(serializedMapping(mapping), sourceId, user.id).run();
  return Response.json({
    preview: {
      paymentId: normalized.paymentId,
      amountMinor: normalized.amountMinor,
      currency: normalized.currency,
      occurredAt: new Date(normalized.occurredAt * 1_000).toISOString(),
      productLabel: normalized.productLabel,
      plan: normalized.details.plan,
      saleType: normalized.details.saleType,
      isSubscription: normalized.isSubscription,
      ...(notificationFields ? {
        notificationFields,
        notificationBody: notificationFieldsBody(notificationFields.filter((field) => field.enabled)) || "Payment received.",
      } : {}),
    },
  });
}

async function activateSource(env: Env, auth: Auth, request: Request, sourceId: string): Promise<Response> {
  const user = await requireUser(auth, request);
  let mapping: WebhookFieldMapping | null = null;
  try {
    mapping = parseMapping(await request.json());
  } catch {
    // The response below covers missing and malformed JSON uniformly.
  }
  if (!mapping) return Response.json({ error: "Preview the current field mapping before activation" }, { status: 400 });
  const mappingJSON = serializedMapping(mapping);
  const previewed = await env.DB.prepare(
    "SELECT mapping_json FROM custom_payment_sources WHERE id = ?1 AND user_id = ?2 AND status = 'setup'",
  ).bind(sourceId, user.id).first<{ mapping_json: string | null }>();
  if (!previewed || previewed.mapping_json !== mappingJSON) {
    return Response.json({ error: "Field mapping changed. Preview it again before activation" }, { status: 409 });
  }
  const updated = await env.DB.prepare(
    `UPDATE custom_payment_sources SET status = 'active', sample_payload_ciphertext = NULL,
      sample_received_at = NULL, sample_error = NULL, updated_at = CURRENT_TIMESTAMP
     WHERE id = ?1 AND user_id = ?2 AND status = 'setup' AND mapping_json = ?3
     RETURNING id, name, status, webhook_token_ciphertext, last_event_received_at,
       last_event_status, last_event_error, last_payment_received_at, created_at, updated_at`,
  ).bind(sourceId, user.id, mappingJSON).first<CustomSourceRow>();
  if (!updated) {
    return Response.json({ error: "Complete a valid field mapping before activation" }, { status: 409 });
  }
  return Response.json({ source: await publicSource(env, updated) });
}

async function testNotification(env: Env, auth: Auth, request: Request, sourceId: string): Promise<Response> {
  const user = await requireUser(auth, request);
  let mapping: WebhookFieldMapping | null = null;
  let delaySeconds = 0;
  try {
    const input = await request.json() as unknown;
    if (input && typeof input === "object" && "mapping" in input) {
      const wrapper = input as Record<string, unknown>;
      mapping = parseMapping(wrapper.mapping);
      if (wrapper.delaySeconds !== undefined) {
        if (
          typeof wrapper.delaySeconds !== "number"
          || !Number.isInteger(wrapper.delaySeconds)
          || wrapper.delaySeconds < 1
          || wrapper.delaySeconds > 60
        ) {
          return Response.json({ error: "Notification delay must be between 1 and 60 seconds" }, { status: 400 });
        }
        delaySeconds = wrapper.delaySeconds;
      }
    } else {
      mapping = parseMapping(input);
    }
  } catch {
    // The response below covers missing and malformed JSON uniformly.
  }
  if (!mapping) return Response.json({ error: "Preview the current notification before testing it" }, { status: 400 });
  const mappingJSON = serializedMapping(mapping);
  const row = await env.DB.prepare(
    `SELECT name, status, sample_payload_ciphertext, mapping_json
     FROM custom_payment_sources
     WHERE id = ?1 AND user_id = ?2 AND status IN ('setup', 'active', 'paused')`,
  ).bind(sourceId, user.id).first<{
    name: string;
    status: "setup" | "active" | "paused";
    sample_payload_ciphertext: string | null;
    mapping_json: string | null;
  }>();
  if (!row) return Response.json({ error: "Payment source not found" }, { status: 404 });
  let body: string;
  let linkedSaleId: string | undefined;
  if (row.status === "setup") {
    if (!row.sample_payload_ciphertext) {
      return Response.json({ error: "Send a sample payment before testing notifications" }, { status: 409 });
    }
    if (row.mapping_json !== mappingJSON) {
      return Response.json({ error: "Your choices changed. Preview the current notification before testing it." }, { status: 409 });
    }
    const payload = JSON.parse(await decryptSecret(
      row.sample_payload_ciphertext,
      env.PROVIDER_TOKEN_ENCRYPTION_KEY,
    ));
    try {
      const normalized = normalizeCustomPayment(payload, mapping, row.name);
      const fields = previewNotificationFields(payload, mapping, normalized);
      body = notificationFieldsBody(fields.filter((field) => field.enabled)) || "Payment received.";
    } catch (error) {
      return Response.json({ error: error instanceof Error ? error.message : "Notification could not be tested" }, { status: 422 });
    }
  } else {
    const current = row.mapping_json ? parseMapping(JSON.parse(row.mapping_json)) : null;
    const currentPaths = new Map((current?.notificationFields ?? []).map((field) => [field.id, field.path]));
    const changesPresentationOnly = current
      && mapping.notificationFields?.length === currentPaths.size
      && mapping.notificationFields.every((field) => currentPaths.get(field.id) === field.path);
    if (!changesPresentationOnly) {
      return Response.json({ error: "Active notification fields can only be renamed, shown, hidden, or reordered" }, { status: 400 });
    }
    const latest = await env.DB.prepare(
      `SELECT id, notification_fields_json, notification_field_values_json FROM sales
       WHERE provider = 'custom' AND provider_account_id = ?1 AND user_id = ?2
         AND notification_fields_json IS NOT NULL
       ORDER BY occurred_at DESC, created_at DESC LIMIT 1`,
    ).bind(sourceId, user.id).first<{
      id: string;
      notification_fields_json: string;
      notification_field_values_json: string | null;
    }>();
    linkedSaleId = latest?.id;
    const rendered = latest
      ? applyHistoricalNotificationPresentation(
        latest.notification_fields_json,
        latest.notification_field_values_json,
        current.notificationFields ?? [],
        mapping.notificationFields ?? [],
      )
      : null;
    const fields = rendered
      ? JSON.parse(rendered.presentation) as Array<{ label: string; value: string }>
      : (mapping.notificationFields ?? [])
        .filter((field) => field.enabled)
        .map((field) => ({ label: field.label, value: "Example value" }));
    body = notificationFieldsBody(fields) || "Payment received.";
  }
  if (delaySeconds > 0) {
    const devices = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM device_tokens WHERE user_id = ?1 AND status = 'active'",
    ).bind(user.id).first<{ count: number }>();
    const registered = Number(devices?.count ?? 0);
    if (registered === 0) {
      return Response.json({ error: "No registered iPhone is ready for notifications" }, { status: 409 });
    }
    const message: TestNotificationMessage = {
      testNotification: { userId: user.id, body, ...(linkedSaleId ? { saleId: linkedSaleId } : {}) },
    };
    await env.NOTIFICATION_QUEUE.send(message, { delaySeconds });
    return Response.json({ scheduled: true, delaySeconds, registered }, { status: 202 });
  }

  const result = await sendTestNotification(env, user.id, body, linkedSaleId);
  if (result.registered === 0) {
    return Response.json({ error: "No registered iPhone is ready for notifications" }, { status: 409 });
  }
  if (result.sent === 0) {
    return Response.json({ error: "Apple did not accept the test notification" }, { status: 502 });
  }
  return Response.json({ sent: result.sent });
}

async function setSourceStatus(
  env: Env,
  auth: Auth,
  request: Request,
  sourceId: string,
  status: "active" | "paused",
): Promise<Response> {
  const user = await requireUser(auth, request);
  const row = await env.DB.prepare(
    `UPDATE custom_payment_sources SET status = ?1, updated_at = CURRENT_TIMESTAMP
     WHERE id = ?2 AND user_id = ?3 AND status IN ('active', 'paused')
     RETURNING id, name, status, webhook_token_ciphertext, last_event_received_at,
       last_event_status, last_event_error, last_payment_received_at, created_at, updated_at`,
  ).bind(status, sourceId, user.id).first<CustomSourceRow>();
  if (!row) return Response.json({ error: "Payment source not found" }, { status: 404 });
  return Response.json({ source: await publicSource(env, row) });
}

async function regenerateWebhookURL(
  env: Env,
  auth: Auth,
  request: Request,
  sourceId: string,
): Promise<Response> {
  const user = await requireUser(auth, request);
  const token = randomToken();
  const [tokenHash, tokenCiphertext] = await Promise.all([
    sha256(token),
    encryptSecret(token, env.PROVIDER_TOKEN_ENCRYPTION_KEY),
  ]);
  const row = await env.DB.prepare(
    `UPDATE custom_payment_sources SET webhook_token_hash = ?1,
      webhook_token_ciphertext = ?2, updated_at = CURRENT_TIMESTAMP
     WHERE id = ?3 AND user_id = ?4
     RETURNING id, name, status, webhook_token_ciphertext, last_event_received_at,
       last_event_status, last_event_error, last_payment_received_at, created_at, updated_at`,
  ).bind(tokenHash, tokenCiphertext, sourceId, user.id).first<CustomSourceRow>();
  if (!row) return Response.json({ error: "Payment source not found" }, { status: 404 });
  return Response.json({ source: await publicSource(env, row) });
}

async function recordActiveWebhookRejection(env: Env, sourceId: string, message: string): Promise<void> {
  await env.DB.prepare(
    `UPDATE custom_payment_sources SET last_event_received_at = CURRENT_TIMESTAMP,
     last_event_status = 'rejected', last_event_error = ?1,
     updated_at = CURRENT_TIMESTAMP WHERE id = ?2 AND status = 'active'`,
  ).bind(message, sourceId).run();
}

async function captureWebhookSample(env: Env, request: Request, token: string): Promise<Response> {
  const tokenHash = await sha256(token);
  const source = await env.DB.prepare(
    `SELECT id, user_id, name, status, mapping_json
     FROM custom_payment_sources WHERE webhook_token_hash = ?1`,
  ).bind(tokenHash).first<{
    id: string;
    user_id: string;
    name: string;
    status: CustomSourceRow["status"];
    mapping_json: string | null;
  }>();
  if (!source) return Response.json({ error: "Webhook not found" }, { status: 404 });
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (contentLength > MAX_CUSTOM_WEBHOOK_BYTES) {
    if (source.status === "active") await recordActiveWebhookRejection(env, source.id, "Payload too large");
    return Response.json({ error: "Payload too large" }, { status: 413 });
  }
  const raw = await request.text();
  if (new TextEncoder().encode(raw).byteLength > MAX_CUSTOM_WEBHOOK_BYTES) {
    if (source.status === "active") await recordActiveWebhookRejection(env, source.id, "Payload too large");
    else if (source.status === "setup") {
      await env.DB.prepare(
        "UPDATE custom_payment_sources SET sample_error = 'Payload too large', updated_at = CURRENT_TIMESTAMP WHERE id = ?1",
      ).bind(source.id).run();
    }
    return Response.json({ error: "Payload too large" }, { status: 413 });
  }
  let payload: unknown;
  try {
    payload = JSON.parse(raw);
  } catch {
    if (source.status === "active") await recordActiveWebhookRejection(env, source.id, "Invalid JSON");
    else if (source.status === "setup") {
      await env.DB.prepare(
        "UPDATE custom_payment_sources SET sample_error = 'Invalid JSON', updated_at = CURRENT_TIMESTAMP WHERE id = ?1",
      ).bind(source.id).run();
    }
    return Response.json({ error: "Invalid JSON" }, { status: 400 });
  }
  if (source.status === "paused") {
    await env.DB.prepare(
      `UPDATE custom_payment_sources SET last_event_received_at = CURRENT_TIMESTAMP,
       last_event_status = 'ignored', last_event_error = NULL,
       health_alerted_at = NULL, updated_at = CURRENT_TIMESTAMP WHERE id = ?1`,
    ).bind(source.id).run();
    return Response.json({ received: true, ignored: "paused" }, { status: 202 });
  }
  if (source.status === "active") {
    if (!source.mapping_json) {
      await recordActiveWebhookRejection(env, source.id, "Payment source mapping is missing");
      return Response.json({ error: "Payment source mapping is missing" }, { status: 409 });
    }
    let normalized: NormalizedCustomPayment;
    let notificationFields: NotificationFieldPreview[] | undefined;
    try {
      const mapping = parseMapping(JSON.parse(source.mapping_json));
      if (!mapping) throw new Error("Payment source mapping is invalid");
      normalized = normalizeCustomPayment(payload, mapping, source.name);
      notificationFields = mapping.notificationFields
        ? previewNotificationFields(payload, mapping, normalized, true)
        : undefined;
    } catch (error) {
      const message = error instanceof Error ? error.message : "Payment could not be mapped";
      console.warn(JSON.stringify({
        message: "custom.webhook.rejected",
        sourceId: source.id,
        reason: message,
      }));
      await recordActiveWebhookRejection(env, source.id, message);
      return Response.json({ error: message }, { status: 422 });
    }
    const paymentFingerprint = await sha256(`${source.id}\u0000${normalized.paymentId}`);
    const scopedPaymentId = `${source.id}:${paymentFingerprint}`;
    const saleId = `custom:${scopedPaymentId}`;
    await env.DB.prepare(
      `INSERT OR IGNORE INTO sales (
        id, user_id, provider, provider_account_id, provider_event_id, provider_payment_id,
        amount_minor, currency, product_label, plan_label, sale_type_label,
        country_code, is_subscription, occurred_at, notification_fields_json,
        notification_field_values_json
      ) VALUES (?1, ?2, 'custom', ?3, ?4, ?4, ?5, ?6, ?7, ?8, ?9, NULL, ?10, ?11, ?12, ?13)`,
    ).bind(
      saleId,
      source.user_id,
      source.id,
      scopedPaymentId,
      normalized.amountMinor,
      normalized.currency,
      normalized.productLabel,
      normalized.details.plan,
      normalized.details.saleType,
      normalized.isSubscription ? 1 : 0,
      normalized.occurredAt,
      notificationFields
        ? JSON.stringify(notificationFields
          .filter((field) => field.enabled)
          .map(({ label, value }) => ({ label, value })))
        : null,
      notificationFields
        ? JSON.stringify(notificationFields
          .filter((field) => field.enabled)
          .map(({ id, value }) => ({ id, value })))
        : null,
    ).run();
    const queued = await enqueueSaleNotification(env, saleId);
    await env.DB.prepare(
      `UPDATE custom_payment_sources SET last_event_received_at = CURRENT_TIMESTAMP,
       last_event_status = ?1, last_event_error = NULL,
       last_payment_received_at = CASE WHEN ?1 = 'accepted' THEN CURRENT_TIMESTAMP
         ELSE last_payment_received_at END,
       health_alerted_at = NULL, updated_at = CURRENT_TIMESTAMP WHERE id = ?2`,
    ).bind(queued ? "accepted" : "duplicate", source.id).run();
    return Response.json({ received: true, duplicate: !queued }, { status: 202 });
  }
  const fields = flattenWebhookPayload(payload);
  if (fields.length === 0) {
    await env.DB.prepare(
      "UPDATE custom_payment_sources SET sample_error = 'No selectable fields found', updated_at = CURRENT_TIMESTAMP WHERE id = ?1",
    ).bind(source.id).run();
    return Response.json({ error: "No selectable fields found" }, { status: 422 });
  }
  const encrypted = await encryptSecret(JSON.stringify(payload), env.PROVIDER_TOKEN_ENCRYPTION_KEY);
  await env.DB.prepare(
    `UPDATE custom_payment_sources SET sample_payload_ciphertext = ?1,
      sample_received_at = CURRENT_TIMESTAMP, sample_error = NULL,
      last_event_received_at = CURRENT_TIMESTAMP, last_event_status = 'received',
      last_event_error = NULL, health_alerted_at = NULL, updated_at = CURRENT_TIMESTAMP
     WHERE id = ?2 AND status = 'setup'`,
  ).bind(encrypted, source.id).run();
  return Response.json({ received: true, sampleCaptured: true }, { status: 202 });
}

export async function handleCustomSourceRequest(
  env: Env,
  auth: Auth,
  request: Request,
): Promise<Response> {
  const url = new URL(request.url);
  const webhookMatch = url.pathname.match(/^\/v1\/webhooks\/custom\/([^/]+)$/);
  if (request.method === "POST" && webhookMatch) {
    return captureWebhookSample(env, request, decodeURIComponent(webhookMatch[1]));
  }
  if (url.pathname === "/v1/custom-sources") {
    if (request.method === "POST") return createSource(env, auth, request);
    if (request.method === "GET") return listSources(env, auth, request);
  }
  const sourceMatch = url.pathname.match(/^\/v1\/custom-sources\/([^/]+)$/);
  if (request.method === "GET" && sourceMatch) {
    return getSource(env, auth, request, decodeURIComponent(sourceMatch[1]));
  }
  const mappingMatch = url.pathname.match(/^\/v1\/custom-sources\/([^/]+)\/mapping$/);
  if (request.method === "POST" && mappingMatch) {
    return saveMapping(env, auth, request, decodeURIComponent(mappingMatch[1]));
  }
  const notificationFieldsMatch = url.pathname.match(/^\/v1\/custom-sources\/([^/]+)\/notification-fields$/);
  if (request.method === "POST" && notificationFieldsMatch) {
    return updateNotificationFields(env, auth, request, decodeURIComponent(notificationFieldsMatch[1]));
  }
  const activateMatch = url.pathname.match(/^\/v1\/custom-sources\/([^/]+)\/activate$/);
  if (request.method === "POST" && activateMatch) {
    return activateSource(env, auth, request, decodeURIComponent(activateMatch[1]));
  }
  const testNotificationMatch = url.pathname.match(/^\/v1\/custom-sources\/([^/]+)\/test-notification$/);
  if (request.method === "POST" && testNotificationMatch) {
    return testNotification(env, auth, request, decodeURIComponent(testNotificationMatch[1]));
  }
  const pauseMatch = url.pathname.match(/^\/v1\/custom-sources\/([^/]+)\/pause$/);
  if (request.method === "POST" && pauseMatch) {
    return setSourceStatus(env, auth, request, decodeURIComponent(pauseMatch[1]), "paused");
  }
  const resumeMatch = url.pathname.match(/^\/v1\/custom-sources\/([^/]+)\/resume$/);
  if (request.method === "POST" && resumeMatch) {
    return setSourceStatus(env, auth, request, decodeURIComponent(resumeMatch[1]), "active");
  }
  const regenerateMatch = url.pathname.match(/^\/v1\/custom-sources\/([^/]+)\/regenerate$/);
  if (request.method === "POST" && regenerateMatch) {
    return regenerateWebhookURL(env, auth, request, decodeURIComponent(regenerateMatch[1]));
  }
  return Response.json({ error: "Not found" }, { status: 404 });
}

const ZERO_DECIMAL_CURRENCIES = new Set([
  "BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "MGA", "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF",
]);
const THREE_DECIMAL_CURRENCIES = new Set(["BHD", "JOD", "KWD", "OMR", "TND"]);

function pointerSegment(value: string): string {
  return value.replace(/~/g, "~0").replace(/\//g, "~1");
}

function decodedPointerSegment(value: string): string {
  return value.replace(/~1/g, "/").replace(/~0/g, "~");
}

export function flattenWebhookPayload(payload: unknown): DiscoveredWebhookField[] {
  const fields: DiscoveredWebhookField[] = [];
  const pending: Array<{ value: unknown; path: string }> = [{ value: payload, path: "" }];
  const visited = new WeakSet<object>();
  while (pending.length > 0) {
    const { value, path } = pending.pop()!;
    if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
      if (path) fields.push({
        path,
        value,
        valueType: typeof value as DiscoveredWebhookField["valueType"],
      });
      continue;
    }
    if (!value || typeof value !== "object" || visited.has(value)) continue;
    visited.add(value);
    const entries = Array.isArray(value)
      ? value.map((item, index) => [String(index), item] as const)
      : Object.entries(value as Record<string, unknown>);
    for (const [key, item] of entries) {
      pending.push({ value: item, path: `${path}/${pointerSegment(key)}` });
    }
  }
  return fields.sort((left, right) => left.path.localeCompare(right.path));
}

function valueAtPointer(payload: unknown, pointer: string | undefined): unknown {
  if (!pointer) return undefined;
  if (!pointer.startsWith("/")) return undefined;
  return pointer
    .slice(1)
    .split("/")
    .map(decodedPointerSegment)
    .reduce<unknown>((current, segment) => {
      if (Array.isArray(current)) {
        const index = Number(segment);
        return Number.isSafeInteger(index) ? current[index] : undefined;
      }
      if (current && typeof current === "object") {
        return (current as Record<string, unknown>)[segment];
      }
      return undefined;
    }, payload);
}

function requiredPaymentId(payload: unknown, pointer: string): string {
  const value = valueAtPointer(payload, pointer);
  if (typeof value === "number" && !Number.isSafeInteger(value)) {
    throw new Error("Mapped payment ID is too large to preserve exactly. Send it as a JSON string or map a string field.");
  }
  if ((typeof value !== "string" && typeof value !== "number") || !String(value).trim()) {
    throw new Error("Mapped payment ID is missing");
  }
  return String(value).trim();
}

function optionalString(payload: unknown, pointer: string | undefined): string | null {
  if (!pointer) return null;
  const value = valueAtPointer(payload, pointer);
  if ((typeof value !== "string" && typeof value !== "number") || !String(value).trim()) return null;
  return String(value).trim().slice(0, 200);
}

function currencyExponent(currency: string): number {
  if (ZERO_DECIMAL_CURRENCIES.has(currency)) return 0;
  if (THREE_DECIMAL_CURRENCIES.has(currency)) return 3;
  return 2;
}

function majorAmountToMinor(value: string, exponent: number): number {
  const normalized = value.trim().replace(/,/g, "");
  const match = normalized.match(/^(\d+)(?:\.(\d+))?$/);
  if (!match) throw new Error("Mapped amount is not a positive number");
  const whole = match[1];
  const fraction = match[2] ?? "";
  if (fraction.length > exponent && /[1-9]/.test(fraction.slice(exponent))) {
    throw new Error("Mapped amount has too many decimal places for its currency");
  }
  const minor = Number(whole) * 10 ** exponent + Number((fraction + "0".repeat(exponent)).slice(0, exponent) || 0);
  if (!Number.isSafeInteger(minor)) throw new Error("Mapped amount is too large");
  return minor;
}

function mappedAmount(payload: unknown, mapping: WebhookFieldMapping, currency: string): number {
  const value = valueAtPointer(payload, mapping.amountPath);
  if ((typeof value !== "string" && typeof value !== "number") || !String(value).trim()) {
    throw new Error("Mapped amount is missing");
  }
  if (mapping.amountUnit === "major") {
    return majorAmountToMinor(String(value), currencyExponent(currency));
  }
  const amount = Number(value);
  if (!Number.isSafeInteger(amount) || amount < 0) throw new Error("Mapped amount must be a whole minor-unit value");
  return amount;
}

function mappedOccurredAt(payload: unknown, pointer: string | undefined, nowSeconds: number): number {
  const value = valueAtPointer(payload, pointer);
  if (value === undefined || value === null || value === "") return nowSeconds;
  if (typeof value === "number") {
    const seconds = value > 10_000_000_000 ? Math.floor(value / 1_000) : Math.floor(value);
    if (Number.isSafeInteger(seconds) && seconds > 0) return seconds;
  }
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    if (!Number.isNaN(parsed)) return Math.floor(parsed / 1_000);
  }
  throw new Error("Mapped payment time is invalid");
}

export function normalizeCustomPayment(
  payload: unknown,
  mapping: WebhookFieldMapping,
  sourceName: string,
  nowSeconds = Math.floor(Date.now() / 1_000),
): NormalizedCustomPayment {
  const paymentId = requiredPaymentId(payload, mapping.paymentIdPath);
  const currency = (
    mapping.fixedCurrency?.trim() || optionalString(payload, mapping.currencyPath) || ""
  ).toUpperCase();
  if (!/^[A-Z]{3}$/.test(currency)) throw new Error("Mapped currency must be a three-letter code");
  const saleType = optionalString(payload, mapping.saleTypePath);
  const plan = optionalString(payload, mapping.planPath);
  return {
    paymentId,
    amountMinor: mappedAmount(payload, mapping, currency),
    currency,
    occurredAt: mappedOccurredAt(payload, mapping.occurredAtPath, nowSeconds),
    productLabel: optionalString(payload, mapping.productPath) ?? sourceName,
    isSubscription: Boolean(saleType && /(subscription|rebill|renew)/i.test(saleType)),
    details: { plan, saleType },
  };
}
