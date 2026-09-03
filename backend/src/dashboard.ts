import type { Auth } from "./auth";
import { requireUser } from "./auth";
import type { Env } from "./env";
import { isValidTimeZone } from "./preferences";

export const dashboardPeriods = ["1w", "4w", "1y", "mtd", "qtd", "ytd", "all"] as const;
export type DashboardPeriod = typeof dashboardPeriods[number];

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

interface CurrencyAggregateRow {
  currency: string;
  payments: number;
  gross_amount_minor: number;
  average_amount_minor: number;
}

interface CountRow { payments: number }
interface EarliestRow { occurred_at: number | null }
interface BucketRow extends CurrencyAggregateRow { bucket_index: number }
interface BreakdownRow extends CurrencyAggregateRow { label: string }
interface BucketWindow extends Window { index: number }

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

export function comparison(current: number, previous: number) {
  if (previous === 0) return current > 0 ? { state: "new" } : { state: "none" };
  return { state: "percent", percent: ((current - previous) / previous) * 100 };
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

function bucketWindows(
  window: Window,
  unit: BucketUnit,
  timeZone: string,
): BucketWindow[] {
  const result: BucketWindow[] = [];
  let cursor = window.start;
  while (cursor < window.end) {
    const end = Math.min(nextBoundary(cursor, unit, timeZone), window.end);
    result.push({ index: result.length, start: cursor, end });
    if (end <= cursor) break;
    cursor = end;
  }
  return result;
}

function moneyTotals(rows: CurrencyAggregateRow[]): MoneyTotal[] {
  return rows.map((row) => ({
    currency: row.currency,
    payments: row.payments,
    grossAmountMinor: row.gross_amount_minor,
    averageAmountMinor: row.average_amount_minor,
  })).sort((left, right) => left.currency.localeCompare(right.currency));
}

function bucketsResponse(windows: BucketWindow[], rows: BucketRow[], currencies: string[]) {
  return windows.map((bucket) => ({
      start: new Date(bucket.start * 1_000).toISOString(),
      end: new Date(bucket.end * 1_000).toISOString(),
      payments: rows.filter((row) => row.bucket_index === bucket.index)
        .reduce((total, row) => total + row.payments, 0),
      amounts: currencies.map((currency) => moneyTotals(rows.filter(
        (row) => row.bucket_index === bucket.index,
      )).find((value) => value.currency === currency) ?? ({
        currency,
        payments: 0,
        grossAmountMinor: 0,
        averageAmountMinor: 0,
      })),
  }));
}

function breakdown(rows: BreakdownRow[]) {
  const grouped = new Map<string, CurrencyAggregateRow[]>();
  for (const row of rows) grouped.set(row.label, [...(grouped.get(row.label) ?? []), row]);
  return [...grouped.entries()].map(([label, values]) => ({
    label,
    amounts: moneyTotals(values),
    payments: values.reduce((total, value) => total + value.payments, 0),
  })).sort((left, right) => right.payments - left.payments || left.label.localeCompare(right.label))
    .map(({ label, amounts }) => ({ label, amounts }));
}

function reportTotals(
  currentPayments: number,
  previousPayments: number,
  currentMoney: MoneyTotal[],
  previousMoney: MoneyTotal[],
  hasPrevious: boolean,
) {
  const currencyCodes = new Set([...currentMoney, ...previousMoney].map((value) => value.currency));
  return {
    payments: {
      current: currentPayments,
      previous: previousPayments,
      comparison: hasPrevious ? comparison(currentPayments, previousPayments) : null,
    },
    currencies: [...currencyCodes].sort().map((currency) => {
      const currentAmount = currentMoney.find((value) => value.currency === currency)?.grossAmountMinor ?? 0;
      const previousAmount = previousMoney.find((value) => value.currency === currency)?.grossAmountMinor ?? 0;
      return {
        currency,
        currentAmountMinor: currentAmount,
        previousAmountMinor: previousAmount,
        comparison: hasPrevious ? comparison(currentAmount, previousAmount) : null,
      };
    }),
  };
}

function countStatement(db: D1Database, userID: string, window: Window): D1PreparedStatement {
  return db.prepare(
    `SELECT COUNT(*) AS payments FROM sales
     WHERE user_id = ?1 AND status = 'succeeded' AND occurred_at >= ?2 AND occurred_at < ?3`,
  ).bind(userID, window.start, window.end);
}

function currencyStatement(db: D1Database, userID: string, window: Window): D1PreparedStatement {
  return db.prepare(
    `SELECT UPPER(currency) AS currency, COUNT(*) AS payments,
            SUM(amount_minor) AS gross_amount_minor,
            CAST(ROUND(1.0 * SUM(amount_minor) / COUNT(*)) AS INTEGER) AS average_amount_minor
     FROM sales
     WHERE user_id = ?1 AND status = 'succeeded' AND occurred_at >= ?2 AND occurred_at < ?3
     GROUP BY UPPER(currency) ORDER BY UPPER(currency)`,
  ).bind(userID, window.start, window.end);
}

function bucketStatement(db: D1Database, userID: string, buckets: BucketWindow[]): D1PreparedStatement {
  if (buckets.length === 0) {
    return db.prepare(
      `SELECT 0 AS bucket_index, '' AS currency, 0 AS payments,
              0 AS gross_amount_minor, 0 AS average_amount_minor WHERE 0`,
    );
  }
  const values = buckets.map((bucket) => `(${bucket.index}, ${bucket.start}, ${bucket.end})`).join(",");
  return db.prepare(
    `WITH buckets(bucket_index, start_at, end_at) AS (VALUES ${values})
     SELECT buckets.bucket_index, UPPER(sales.currency) AS currency,
            COUNT(*) AS payments, SUM(sales.amount_minor) AS gross_amount_minor,
            CAST(ROUND(1.0 * SUM(sales.amount_minor) / COUNT(*)) AS INTEGER) AS average_amount_minor
     FROM buckets
     JOIN sales ON sales.occurred_at >= buckets.start_at AND sales.occurred_at < buckets.end_at
     WHERE sales.user_id = ?1 AND sales.status = 'succeeded'
     GROUP BY buckets.bucket_index, UPPER(sales.currency)
     ORDER BY buckets.bucket_index, UPPER(sales.currency)`,
  ).bind(userID);
}

function breakdownStatement(
  db: D1Database,
  userID: string,
  window: Window,
  dimension: "product" | "source",
): D1PreparedStatement {
  const label = dimension === "product"
    ? "sales.product_label"
    : `CASE sales.provider
         WHEN 'custom' THEN COALESCE(custom_payment_sources.name, 'Custom webhook')
         WHEN 'stripe' THEN 'Stripe'
         ELSE 'PayPal'
       END`;
  return db.prepare(
    `SELECT ${label} AS label, UPPER(sales.currency) AS currency,
            COUNT(*) AS payments, SUM(sales.amount_minor) AS gross_amount_minor,
            CAST(ROUND(1.0 * SUM(sales.amount_minor) / COUNT(*)) AS INTEGER) AS average_amount_minor
     FROM sales
     LEFT JOIN custom_payment_sources
       ON sales.provider = 'custom'
      AND custom_payment_sources.id = sales.provider_account_id
      AND custom_payment_sources.user_id = sales.user_id
     WHERE sales.user_id = ?1 AND sales.status = 'succeeded'
       AND sales.occurred_at >= ?2 AND sales.occurred_at < ?3
     GROUP BY ${label}, UPPER(sales.currency)`,
  ).bind(userID, window.start, window.end);
}

export async function getDashboard(
  env: Env,
  auth: Auth,
  request: Request,
  now: number = Math.floor(Date.now() / 1_000),
  consistencyAttempt = 0,
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

  const period = periodValue as DashboardPeriod;
  const earliest = period === "all"
    ? await env.DB.prepare(
      `SELECT MIN(occurred_at) AS occurred_at FROM sales
       WHERE user_id = ?1 AND status = 'succeeded' AND occurred_at < ?2`,
    ).bind(user.id, now).first<{ occurred_at: number | null }>()
    : null;
  const windows = reportWindows(
    period,
    preference.reporting_timezone,
    now,
    earliest?.occurred_at ?? undefined,
  );
  const todayWindow = { start: localMidnight(now, preference.reporting_timezone), end: now };
  const unit = bucketUnit(period, windows.current);
  const currentBuckets = bucketWindows(windows.current, unit, preference.reporting_timezone);
  const previousWindow = windows.previous ?? { start: 0, end: 0 };
  const previousBuckets = windows.previous
    ? bucketWindows(windows.previous, unit, preference.reporting_timezone)
    : [];
  const batch = await env.DB.batch([
    env.DB.prepare(
      `SELECT MIN(occurred_at) AS occurred_at FROM sales
       WHERE user_id = ?1 AND status = 'succeeded' AND occurred_at < ?2`,
    ).bind(user.id, now),
    countStatement(env.DB, user.id, todayWindow),
    currencyStatement(env.DB, user.id, todayWindow),
    countStatement(env.DB, user.id, windows.current),
    currencyStatement(env.DB, user.id, windows.current),
    countStatement(env.DB, user.id, previousWindow),
    currencyStatement(env.DB, user.id, previousWindow),
    bucketStatement(env.DB, user.id, currentBuckets),
    bucketStatement(env.DB, user.id, previousBuckets),
    breakdownStatement(env.DB, user.id, windows.current, "product"),
    breakdownStatement(env.DB, user.id, windows.current, "source"),
  ]);
  const rows = <Row>(index: number) => batch[index].results as Row[];
  const transactionalEarliest = rows<EarliestRow>(0)[0]?.occurred_at ?? undefined;
  if (period === "all" && transactionalEarliest !== (earliest?.occurred_at ?? undefined)) {
    if (consistencyAttempt >= 2) {
      return Response.json({ error: "Dashboard changed while loading" }, { status: 503 });
    }
    return getDashboard(env, auth, request, now, consistencyAttempt + 1);
  }
  const todayPayments = rows<CountRow>(1)[0]?.payments ?? 0;
  const todayMoney = moneyTotals(rows<CurrencyAggregateRow>(2));
  const currentPayments = rows<CountRow>(3)[0]?.payments ?? 0;
  const currentMoney = moneyTotals(rows<CurrencyAggregateRow>(4));
  const previousPayments = rows<CountRow>(5)[0]?.payments ?? 0;
  const previousMoney = moneyTotals(rows<CurrencyAggregateRow>(6));
  const currentSeriesRows = rows<BucketRow>(7);
  const previousSeriesRows = rows<BucketRow>(8);
  const reportCurrencies = [...new Set([...currentMoney, ...previousMoney].map((value) => value.currency))].sort();

  return Response.json({
    reportingTimezone: preference.reporting_timezone,
    generatedAt: new Date(now * 1_000).toISOString(),
    period,
    today: {
      start: new Date(todayWindow.start * 1_000).toISOString(),
      end: new Date(todayWindow.end * 1_000).toISOString(),
      payments: todayPayments,
      currencies: todayMoney,
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
      totals: reportTotals(
        currentPayments,
        previousPayments,
        currentMoney,
        previousMoney,
        windows.previous !== null,
      ),
      currentSeries: bucketsResponse(currentBuckets, currentSeriesRows, reportCurrencies),
      previousSeries: bucketsResponse(previousBuckets, previousSeriesRows, reportCurrencies),
      products: breakdown(rows<BreakdownRow>(9)),
      sources: breakdown(rows<BreakdownRow>(10)),
    },
  });
}
