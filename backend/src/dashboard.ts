import type { Auth } from "./auth";
import { requireUser } from "./auth";
import type { Env, SaleSource } from "./env";
import { isValidTimeZone } from "./preferences";

export const dashboardPeriods = ["1w", "4w", "1y", "mtd", "qtd", "ytd", "all"] as const;
export type DashboardPeriod = typeof dashboardPeriods[number];

interface SaleRow {
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
  grossAmountMinor: number;
  averageAmountMinor: number;
}

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
  return Math.floor(candidate / 1_000);
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

function rowsIn(rows: SaleRow[], window: Window): SaleRow[] {
  return rows.filter((row) => row.occurred_at >= window.start && row.occurred_at < window.end);
}

function moneyTotals(rows: SaleRow[]): MoneyTotal[] {
  const totals = new Map<string, { amount: number; count: number }>();
  for (const row of rows) {
    const currency = row.currency.toUpperCase();
    const prior = totals.get(currency) ?? { amount: 0, count: 0 };
    prior.amount += row.amount_minor;
    prior.count += 1;
    totals.set(currency, prior);
  }
  return [...totals.entries()].sort(([left], [right]) => left.localeCompare(right)).map(
    ([currency, value]) => ({
      currency,
      grossAmountMinor: value.amount,
      averageAmountMinor: Math.round(value.amount / value.count),
    }),
  );
}

export function comparison(current: number, previous: number) {
  if (previous === 0) return current > 0 ? { state: "new" } : { state: "none" };
  return { state: "percent", percent: ((current - previous) / previous) * 100 };
}

function breakdown(rows: SaleRow[], label: (row: SaleRow) => string) {
  const grouped = new Map<string, SaleRow[]>();
  for (const row of rows) {
    const key = label(row);
    grouped.set(key, [...(grouped.get(key) ?? []), row]);
  }
  return [...grouped.entries()].map(([name, values]) => ({
    label: name,
    payments: values.length,
    amounts: moneyTotals(values),
  })).sort((left, right) => right.payments - left.payments || left.label.localeCompare(right.label));
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

function buckets(
  rows: SaleRow[],
  window: Window,
  unit: BucketUnit,
  timeZone: string,
  currencies: string[],
) {
  const result: Array<{ start: string; end: string; payments: number; amounts: MoneyTotal[] }> = [];
  let cursor = window.start;
  while (cursor < window.end) {
    const end = Math.min(nextBoundary(cursor, unit, timeZone), window.end);
    const values = rowsIn(rows, { start: cursor, end });
    result.push({
      start: new Date(cursor * 1_000).toISOString(),
      end: new Date(end * 1_000).toISOString(),
      payments: values.length,
      amounts: currencies.map((currency) => moneyTotals(values).find((value) => value.currency === currency) ?? ({
        currency,
        grossAmountMinor: 0,
        averageAmountMinor: 0,
      })),
    });
    if (end <= cursor) break;
    cursor = end;
  }
  return result;
}

function reportTotals(current: SaleRow[], previous: SaleRow[]) {
  const currentMoney = moneyTotals(current);
  const previousMoney = moneyTotals(previous);
  const currencyCodes = new Set([...currentMoney, ...previousMoney].map((value) => value.currency));
  return {
    payments: {
      current: current.length,
      previous: previous.length,
      comparison: comparison(current.length, previous.length),
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

  const rows: SaleRow[] = [];
  const pageSize = 1_000;
  while (true) {
    const result = await env.DB.prepare(
      `SELECT sales.amount_minor, sales.currency, sales.product_label, sales.provider,
              sales.occurred_at, custom_payment_sources.name AS source_name
       FROM sales
       LEFT JOIN custom_payment_sources
         ON sales.provider = 'custom'
        AND custom_payment_sources.id = sales.provider_account_id
        AND custom_payment_sources.user_id = sales.user_id
       WHERE sales.user_id = ?1 AND sales.status = 'succeeded' AND sales.occurred_at < ?2
       ORDER BY sales.occurred_at, sales.id
       LIMIT ?3 OFFSET ?4`,
    ).bind(user.id, now, pageSize, rows.length).all<SaleRow>();
    rows.push(...result.results);
    if (result.results.length < pageSize) break;
  }
  const period = periodValue as DashboardPeriod;
  const windows = reportWindows(period, preference.reporting_timezone, now, rows[0]?.occurred_at);
  const todayWindow = { start: localMidnight(now, preference.reporting_timezone), end: now };
  const currentRows = rowsIn(rows, windows.current);
  const previousRows = windows.previous ? rowsIn(rows, windows.previous) : [];
  const unit = bucketUnit(period, windows.current);
  const reportCurrencies = [...new Set([...currentRows, ...previousRows].map((row) => row.currency.toUpperCase()))].sort();
  const sourceLabel = (row: SaleRow) => row.provider === "custom"
    ? (row.source_name ?? "Custom webhook")
    : row.provider === "stripe" ? "Stripe" : "PayPal";

  return Response.json({
    reportingTimezone: preference.reporting_timezone,
    generatedAt: new Date(now * 1_000).toISOString(),
    period,
    today: {
      start: new Date(todayWindow.start * 1_000).toISOString(),
      end: new Date(todayWindow.end * 1_000).toISOString(),
      payments: rowsIn(rows, todayWindow).length,
      currencies: moneyTotals(rowsIn(rows, todayWindow)),
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
      totals: reportTotals(currentRows, previousRows),
      currentSeries: buckets(currentRows, windows.current, unit, preference.reporting_timezone, reportCurrencies),
      previousSeries: windows.previous
        ? buckets(previousRows, windows.previous, unit, preference.reporting_timezone, reportCurrencies)
        : [],
      products: breakdown(currentRows, (row) => row.product_label),
      sources: breakdown(currentRows, sourceLabel),
    },
  });
}
