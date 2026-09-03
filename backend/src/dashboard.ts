import type { Auth } from "./auth";
import { requireUser } from "./auth";
import type { Env, SaleSource } from "./env";
import { isValidTimeZone } from "./preferences";

export const dashboardPeriods = ["1w", "4w", "1y", "mtd", "qtd", "ytd", "all"] as const;
export type DashboardPeriod = typeof dashboardPeriods[number];

interface SaleRow {
  id: string;
  ingestion_sequence: number;
  amount_minor: number;
  currency: string;
  product_label: string;
  provider: SaleSource;
  source_name: string | null;
  occurred_at: number;
}

interface CivilDate {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
}

interface Window {
  start: number;
  end: number;
}

interface MoneyTotal {
  currency: string;
  payments: number;
  grossAmountMinor: number;
  averageAmountMinor: number;
}

interface Aggregate {
  payments: number;
  money: Map<string, { amount: number; count: number }>;
}

interface BucketAggregate extends Aggregate, Window {}

const formatterCache = new Map<string, Intl.DateTimeFormat>();

function formatter(timeZone: string): Intl.DateTimeFormat {
  const cached = formatterCache.get(timeZone);
  if (cached) return cached;
  const value = new Intl.DateTimeFormat("en-US", {
    timeZone,
    calendar: "gregory",
    numberingSystem: "latn",
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
  formatterCache.set(timeZone, value);
  return value;
}

function civilAt(epochSeconds: number, timeZone: string): CivilDate {
  const values: Record<string, number> = {};
  for (const part of formatter(timeZone).formatToParts(new Date(epochSeconds * 1_000))) {
    if (part.type !== "literal") values[part.type] = Number(part.value);
  }
  return {
    year: values.year,
    month: values.month,
    day: values.day,
    hour: values.hour,
    minute: values.minute,
    second: values.second,
  };
}

function offsetAt(epochMillis: number, timeZone: string): number {
  const civil = civilAt(Math.floor(epochMillis / 1_000), timeZone);
  return Date.UTC(civil.year, civil.month - 1, civil.day, civil.hour, civil.minute, civil.second)
    - Math.floor(epochMillis / 1_000) * 1_000;
}

export function epochForCivil(civil: CivilDate, timeZone: string): number {
  const utcGuess = Date.UTC(
    civil.year, civil.month - 1, civil.day, civil.hour, civil.minute, civil.second,
  );
  let candidate = utcGuess;
  for (let iteration = 0; iteration < 4; iteration += 1) {
    const next = utcGuess - offsetAt(candidate, timeZone);
    if (next === candidate) break;
    candidate = next;
  }
  const candidateSeconds = Math.floor(candidate / 1_000);
  const resolved = civilAt(candidateSeconds, timeZone);
  if (
    resolved.year === civil.year
    && resolved.month === civil.month
    && resolved.day === civil.day
    && resolved.hour === civil.hour
    && resolved.minute === civil.minute
    && resolved.second === civil.second
  ) return candidateSeconds;

  // Some zones advance their clocks at midnight. That wall-clock time does
  // not exist, so use the first real instant on the requested local date.
  const searchStart = Math.floor((utcGuess - 18 * 60 * 60 * 1_000) / 1_000);
  const searchEnd = Math.floor((utcGuess + 18 * 60 * 60 * 1_000) / 1_000);
  for (let probe = searchStart; probe <= searchEnd; probe += 60) {
    const value = civilAt(probe, timeZone);
    if (value.year !== civil.year || value.month !== civil.month || value.day !== civil.day) continue;
    const requestedClock = civil.hour * 3_600 + civil.minute * 60 + civil.second;
    const actualClock = value.hour * 3_600 + value.minute * 60 + value.second;
    if (actualClock < requestedClock) continue;
    for (let second = Math.max(searchStart, probe - 59); second <= probe; second += 1) {
      const exact = civilAt(second, timeZone);
      if (exact.year === civil.year && exact.month === civil.month && exact.day === civil.day) {
        const exactClock = exact.hour * 3_600 + exact.minute * 60 + exact.second;
        if (exactClock >= requestedClock) return second;
      }
    }
    return probe;
  }
  throw new Error(`Local date does not exist in timezone ${timeZone}`);
}

function shiftedDate(civil: CivilDate, values: { days?: number; months?: number; years?: number }): CivilDate {
  if (values.years) {
    const year = civil.year + values.years;
    const lastDay = new Date(Date.UTC(year, civil.month, 0)).getUTCDate();
    return { ...civil, year, day: Math.min(civil.day, lastDay) };
  }
  const date = new Date(Date.UTC(
    civil.year,
    civil.month - 1 + (values.months ?? 0),
    civil.day + (values.days ?? 0),
  ));
  return {
    ...civil,
    year: date.getUTCFullYear(),
    month: date.getUTCMonth() + 1,
    day: date.getUTCDate(),
  };
}

function localMidnight(epochSeconds: number, timeZone: string): number {
  const civil = civilAt(epochSeconds, timeZone);
  return epochForCivil({ ...civil, hour: 0, minute: 0, second: 0 }, timeZone);
}

export function reportWindows(
  period: DashboardPeriod,
  timeZone: string,
  now: number,
  earliestSale?: number,
): { current: Window; previous: Window | null } {
  const todayCivil = { ...civilAt(now, timeZone), hour: 0, minute: 0, second: 0 };
  let start: number;
  switch (period) {
  case "1w":
    start = epochForCivil(shiftedDate(todayCivil, { days: -6 }), timeZone);
    break;
  case "4w":
    start = epochForCivil(shiftedDate(todayCivil, { days: -27 }), timeZone);
    break;
  case "1y":
    start = epochForCivil(shiftedDate(todayCivil, { years: -1 }), timeZone);
    break;
  case "mtd":
    start = epochForCivil({ ...todayCivil, day: 1 }, timeZone);
    break;
  case "qtd":
    start = epochForCivil({ ...todayCivil, month: Math.floor((todayCivil.month - 1) / 3) * 3 + 1, day: 1 }, timeZone);
    break;
  case "ytd":
    start = epochForCivil({ ...todayCivil, month: 1, day: 1 }, timeZone);
    break;
  case "all":
    start = Math.min(earliestSale ?? localMidnight(now, timeZone), now);
    return { current: { start, end: now }, previous: null };
  }
  const elapsed = now - start;
  return {
    current: { start, end: now },
    previous: { start: start - elapsed, end: start },
  };
}

function contains(window: Window, occurredAt: number): boolean {
  return occurredAt >= window.start && occurredAt < window.end;
}

function aggregate(): Aggregate {
  return { payments: 0, money: new Map() };
}

function add(aggregateValue: Aggregate, row: SaleRow): void {
  aggregateValue.payments += 1;
  const currency = row.currency.toUpperCase();
  const prior = aggregateValue.money.get(currency) ?? { amount: 0, count: 0 };
  prior.amount += row.amount_minor;
  prior.count += 1;
  aggregateValue.money.set(currency, prior);
}

function moneyTotals(value: Aggregate): MoneyTotal[] {
  return [...value.money.entries()].sort(([left], [right]) => left.localeCompare(right)).map(
    ([currency, value]) => ({
      currency,
      payments: value.count,
      grossAmountMinor: value.amount,
      averageAmountMinor: Math.round(value.amount / value.count),
    }),
  );
}

export function comparison(current: number, previous: number) {
  if (previous === 0) return current > 0 ? { state: "new" } : { state: "none" };
  return { state: "percent", percent: ((current - previous) / previous) * 100 };
}

function addBreakdown(grouped: Map<string, Aggregate>, name: string, row: SaleRow): void {
  const value = grouped.get(name) ?? aggregate();
  add(value, row);
  grouped.set(name, value);
}

function breakdown(grouped: Map<string, Aggregate>) {
  return [...grouped.entries()]
    .sort(([leftName, left], [rightName, right]) => (
      right.payments - left.payments || leftName.localeCompare(rightName)
    ))
    .map(([name, value]) => ({
    label: name,
    amounts: moneyTotals(value),
  }));
}

type BucketUnit = "day" | "week" | "month" | "year";

function bucketUnit(period: DashboardPeriod, window: Window): BucketUnit {
  if (["1w", "4w", "mtd"].includes(period)) return "day";
  if (period === "qtd") return "week";
  if (["1y", "ytd"].includes(period)) return "month";
  const days = (window.end - window.start) / 86_400;
  return days <= 90 ? "day" : days <= 1_095 ? "month" : "year";
}

function nextBoundary(start: number, unit: BucketUnit, timeZone: string): number {
  const civil = civilAt(start, timeZone);
  const midnight = { ...civil, hour: 0, minute: 0, second: 0 };
  if (unit === "day") return epochForCivil(shiftedDate(midnight, { days: 1 }), timeZone);
  if (unit === "week") return epochForCivil(shiftedDate(midnight, { days: 7 }), timeZone);
  if (unit === "month") return epochForCivil(shiftedDate(midnight, { months: 1 }), timeZone);
  return epochForCivil(shiftedDate(midnight, { years: 1 }), timeZone);
}

function bucketAggregates(
  window: Window,
  unit: BucketUnit,
  timeZone: string,
): BucketAggregate[] {
  const result: BucketAggregate[] = [];
  let cursor = window.start;
  while (cursor < window.end) {
    const end = Math.min(nextBoundary(cursor, unit, timeZone), window.end);
    result.push({ start: cursor, end, ...aggregate() });
    if (end <= cursor) break;
    cursor = end;
  }
  return result;
}

function addToBucket(buckets: BucketAggregate[], row: SaleRow): void {
  const bucket = buckets.find((value) => contains(value, row.occurred_at));
  if (bucket) add(bucket, row);
}

function bucketsResponse(buckets: BucketAggregate[], currencies: string[]) {
  return buckets.map((bucket) => ({
      start: new Date(bucket.start * 1_000).toISOString(),
      end: new Date(bucket.end * 1_000).toISOString(),
      payments: bucket.payments,
      amounts: currencies.map((currency) => moneyTotals(bucket).find((value) => value.currency === currency) ?? ({
        currency,
        payments: 0,
        grossAmountMinor: 0,
        averageAmountMinor: 0,
      })),
  }));
}

function reportTotals(current: Aggregate, previous: Aggregate) {
  const currentMoney = moneyTotals(current);
  const previousMoney = moneyTotals(previous);
  const currencyCodes = new Set([...currentMoney, ...previousMoney].map((value) => value.currency));
  return {
    payments: {
      current: current.payments,
      previous: previous.payments,
      comparison: comparison(current.payments, previous.payments),
    },
    currencies: [...currencyCodes].sort().map((currency) => {
      const currentAmount = currentMoney.find((value) => value.currency === currency)?.grossAmountMinor ?? 0;
      const previousAmount = previousMoney.find((value) => value.currency === currency)?.grossAmountMinor ?? 0;
      return {
        currency,
        currentAmountMinor: currentAmount,
        previousAmountMinor: previousAmount,
        comparison: comparison(currentAmount, previousAmount),
      };
    }),
  };
}

export async function getDashboard(
  env: Env,
  auth: Auth,
  request: Request,
  now: number = Math.floor(Date.now() / 1_000),
  readOptions: { pageSize?: number; onPage?: (page: number) => Promise<void> } = {},
): Promise<Response> {
  const user = await requireUser(auth, request);
  const url = new URL(request.url);
  const periodValue = url.searchParams.get("period") ?? "4w";
  if (!dashboardPeriods.includes(periodValue as DashboardPeriod)) {
    return Response.json({ error: "Invalid dashboard period" }, { status: 400 });
  }
  const preference = await env.DB.prepare(
    "SELECT reporting_timezone FROM user_preferences WHERE user_id = ?1",
  ).bind(user.id).first<{ reporting_timezone: string }>();
  if (!preference || !isValidTimeZone(preference.reporting_timezone)) {
    return Response.json({ error: "Reporting timezone is not configured" }, { status: 409 });
  }

  const snapshot = await env.DB.prepare(
    `SELECT COALESCE(MAX(sales_ingestion_order.sequence), 0) AS sequence,
            MIN(sales.occurred_at) AS earliest
     FROM sales
     JOIN sales_ingestion_order ON sales_ingestion_order.sale_id = sales.id
     WHERE sales.user_id = ?1 AND sales.status = 'succeeded' AND sales.occurred_at < ?2`,
  ).bind(user.id, now).first<{ sequence: number; earliest: number | null }>();
  const period = periodValue as DashboardPeriod;
  const windows = reportWindows(
    period,
    preference.reporting_timezone,
    now,
    snapshot?.earliest ?? undefined,
  );
  const todayWindow = { start: localMidnight(now, preference.reporting_timezone), end: now };
  const unit = bucketUnit(period, windows.current);
  const today = aggregate();
  const current = aggregate();
  const previous = aggregate();
  const currentBuckets = bucketAggregates(windows.current, unit, preference.reporting_timezone);
  const previousBuckets = windows.previous
    ? bucketAggregates(windows.previous, unit, preference.reporting_timezone)
    : [];
  const products = new Map<string, Aggregate>();
  const sources = new Map<string, Aggregate>();
  const sourceLabel = (row: SaleRow) => row.provider === "custom"
    ? (row.source_name ?? "Custom webhook")
    : row.provider === "stripe" ? "Stripe" : "PayPal";
  const pageSize = readOptions.pageSize ?? 1_000;
  let page = 0;
  const scanStart = windows.previous?.start ?? windows.current.start;
  let cursorSequence = 0;
  while (true) {
    const result = await env.DB.prepare(
      `SELECT sales.id, sales_ingestion_order.sequence AS ingestion_sequence,
              sales.amount_minor, sales.currency, sales.product_label, sales.provider,
              sales.occurred_at, custom_payment_sources.name AS source_name
       FROM sales
       JOIN sales_ingestion_order ON sales_ingestion_order.sale_id = sales.id
       LEFT JOIN custom_payment_sources
         ON sales.provider = 'custom'
        AND custom_payment_sources.id = sales.provider_account_id
        AND custom_payment_sources.user_id = sales.user_id
       WHERE sales.user_id = ?1 AND sales.status = 'succeeded' AND sales.occurred_at < ?2
         AND sales_ingestion_order.sequence <= ?3
         AND sales.occurred_at >= ?4
         AND sales_ingestion_order.sequence > ?5
       ORDER BY sales_ingestion_order.sequence
       LIMIT ?6`,
    ).bind(
      user.id,
      now,
      snapshot?.sequence ?? 0,
      scanStart,
      cursorSequence,
      pageSize,
    ).all<SaleRow>();
    for (const row of result.results) {
      if (contains(todayWindow, row.occurred_at)) add(today, row);
      if (contains(windows.current, row.occurred_at)) {
        add(current, row);
        addToBucket(currentBuckets, row);
        addBreakdown(products, row.product_label, row);
        addBreakdown(sources, sourceLabel(row), row);
      } else if (windows.previous && contains(windows.previous, row.occurred_at)) {
        add(previous, row);
        addToBucket(previousBuckets, row);
      }
    }
    await readOptions.onPage?.(page);
    page += 1;
    if (result.results.length < pageSize) break;
    const last = result.results[result.results.length - 1];
    cursorSequence = last.ingestion_sequence;
  }
  const reportCurrencies = [...new Set([...current.money.keys(), ...previous.money.keys()])].sort();

  return Response.json({
    reportingTimezone: preference.reporting_timezone,
    generatedAt: new Date(now * 1_000).toISOString(),
    period,
    today: {
      start: new Date(todayWindow.start * 1_000).toISOString(),
      end: new Date(todayWindow.end * 1_000).toISOString(),
      payments: today.payments,
      currencies: moneyTotals(today),
    },
    report: {
      current: {
        start: new Date(windows.current.start * 1_000).toISOString(),
        end: new Date(windows.current.end * 1_000).toISOString(),
      },
      previous: windows.previous ? {
        start: new Date(windows.previous.start * 1_000).toISOString(),
        end: new Date(windows.previous.end * 1_000).toISOString(),
      } : null,
      totals: reportTotals(current, previous),
      currentSeries: bucketsResponse(currentBuckets, reportCurrencies),
      previousSeries: bucketsResponse(previousBuckets, reportCurrencies),
      products: breakdown(products),
      sources: breakdown(sources),
    },
  });
}
