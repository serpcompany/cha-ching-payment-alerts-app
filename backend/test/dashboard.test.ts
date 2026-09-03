import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { Auth } from "../src/auth";
import { comparison, dashboardDayWindow, getDashboard, reportWindows } from "../src/dashboard";
import type { Env } from "../src/env";
import { getPreferences, updatePreferences } from "../src/preferences";
import { applyMigration } from "./apply-migration";

function authFor(userId: string): Auth {
  return {
    api: {
      getSession: async () => ({
        user: { id: userId, name: "Founder", email: `${userId}@example.test` },
        session: { id: `session-${userId}` },
      }),
    },
  } as unknown as Auth;
}

function epoch(iso: string): number {
  return Math.floor(new Date(iso).getTime() / 1_000);
}

describe("dashboard date windows", () => {
  it("uses timezone-local midnight across DST and positive offsets", () => {
    const newYorkNow = epoch("2026-03-09T16:00:00Z");
    const newYork = reportWindows("1w", "America/New_York", newYorkNow);
    expect(new Date(newYork.current.start * 1_000).toISOString()).toBe("2026-03-03T05:00:00.000Z");

    const tokyoNow = epoch("2026-09-03T03:00:00Z");
    const tokyo = reportWindows("mtd", "Asia/Tokyo", tokyoNow);
    expect(new Date(tokyo.current.start * 1_000).toISOString()).toBe("2026-08-31T15:00:00.000Z");
  });

  it("uses the first valid instant when a timezone skips midnight", () => {
    const now = epoch("2019-09-08T12:00:00Z");
    const window = reportWindows("mtd", "America/Santiago", now);
    expect(new Date(window.current.start * 1_000).toISOString()).toBe("2019-09-01T04:00:00.000Z");

    const skippedMidnightDay = reportWindows("1w", "America/Santiago", epoch("2019-09-14T12:00:00Z"));
    expect(new Date(skippedMidnightDay.current.start * 1_000).toISOString()).toBe("2019-09-08T04:00:00.000Z");
  });

  it("moves the daily summary through complete reporting-timezone days", () => {
    const now = epoch("2026-03-09T16:00:00Z");
    expect(dashboardDayWindow("America/New_York", now, 0)).toEqual({
      start: epoch("2026-03-09T04:00:00Z"),
      end: now,
    });
    expect(dashboardDayWindow("America/New_York", now, 1)).toEqual({
      start: epoch("2026-03-08T05:00:00Z"),
      end: epoch("2026-03-09T04:00:00Z"),
    });
    expect(dashboardDayWindow("America/New_York", now, 2)).toEqual({
      start: epoch("2026-03-07T05:00:00Z"),
      end: epoch("2026-03-08T05:00:00Z"),
    });
  });

  it("clamps leap day and finds quarter and year boundaries", () => {
    const leapDay = epoch("2024-02-29T12:00:00Z");
    expect(new Date(reportWindows("1y", "UTC", leapDay).current.start * 1_000).toISOString())
      .toBe("2023-02-28T00:00:00.000Z");
    const now = epoch("2026-08-15T12:00:00Z");
    expect(new Date(reportWindows("qtd", "UTC", now).current.start * 1_000).toISOString())
      .toBe("2026-07-01T00:00:00.000Z");
    expect(new Date(reportWindows("ytd", "UTC", now).current.start * 1_000).toISOString())
      .toBe("2026-01-01T00:00:00.000Z");
  });

  it("supports every period and equal-elapsed previous windows", () => {
    const now = epoch("2026-09-03T12:00:00Z");
    for (const period of ["1w", "4w", "1y", "mtd", "qtd", "ytd"] as const) {
      const windows = reportWindows(period, "UTC", now);
      expect(windows.previous).not.toBeNull();
      expect(windows.current.end - windows.current.start)
        .toBe(windows.previous!.end - windows.previous!.start);
      expect(windows.previous!.end).toBe(windows.current.start);
    }
    const all = reportWindows("all", "UTC", now, epoch("2020-01-02T03:04:05Z"));
    expect(all.previous).toBeNull();
    expect(all.current.start).toBe(epoch("2020-01-02T03:04:05Z"));
  });

  it("defines all comparison states", () => {
    expect(comparison(10, 0)).toEqual({ state: "new" });
    expect(comparison(0, 0)).toEqual({ state: "none" });
    expect(comparison(0, 10)).toEqual({ state: "percent", percent: -100 });
    expect(comparison(12, 10)).toEqual({ state: "percent", percent: 20 });
  });
});

describe("dashboard preferences and aggregation", () => {
  let miniflare: Miniflare;
  let env: Env;

  beforeEach(async () => {
    miniflare = new Miniflare({
      modules: true,
      script: "export default { fetch() { return new Response('ok') } }",
      d1Databases: ["DB"],
    });
    const db = await miniflare.getD1Database("DB");
    const migrations = [
      "0001_initial.sql", "0002_sales_and_notifications.sql", "0003_anonymous_simulator_user.sql",
      "0004_nullable_provider_access_token.sql", "0005_custom_payment_sources.sql",
      "0006_provider_connection_activity.sql", "0007_provider_event_disposition.sql",
      "0008_notification_queue_claims.sql", "0009_custom_notification_fields.sql",
      "0010_reconcile_custom_payment_history_presentation.sql", "0011_retain_custom_payment_field_values.sql",
      "0012_custom_source_health.sql", "0013_product_entitlements.sql",
      "0014_apple_account_deletion_credentials.sql", "0015_user_preferences.sql",
    ];
    for (const migration of migrations) {
      await applyMigration(db, migration);
    }
    await db.batch(["one", "two"].map((id) => db.prepare(
      "INSERT INTO user (id, name, email, created_at, updated_at) VALUES (?1, 'Founder', ?2, ?3, ?3)",
    ).bind(id, `${id}@example.test`, Date.now())));
    env = { DB: db } as unknown as Env;
  });

  afterEach(async () => miniflare.dispose());

  it("initializes once, validates, replaces explicitly, and isolates users", async () => {
    const initialize = (user: string, zone: string) => updatePreferences(
      env,
      authFor(user),
      new Request("https://api.test/v1/preferences", {
        method: "PUT",
        body: JSON.stringify({ reportingTimezone: zone, initializeOnly: true }),
      }),
    );
    expect(await (await initialize("one", "Asia/Tokyo")).json()).toEqual({ reportingTimezone: "Asia/Tokyo" });
    expect(await (await initialize("one", "America/New_York")).json()).toEqual({ reportingTimezone: "Asia/Tokyo" });
    expect(await (await initialize("two", "Europe/London")).json()).toEqual({ reportingTimezone: "Europe/London" });

    const invalid = await initialize("one", "Moon/Sea_of_Tranquility");
    expect(invalid.status).toBe(400);

    const replacement = await updatePreferences(env, authFor("one"), new Request("https://api.test/v1/preferences", {
      method: "PUT",
      body: JSON.stringify({ reportingTimezone: "America/New_York" }),
    }));
    expect(await replacement.json()).toEqual({ reportingTimezone: "America/New_York" });
    const second = await getPreferences(env, authFor("two"), new Request("https://api.test/v1/preferences"));
    expect(await second.json()).toEqual({ reportingTimezone: "Europe/London" });
  });

  it("rejects future, fractional, and unbounded daily-summary offsets", async () => {
    for (const dayOffset of ["-1", "1.5", "36501", "tomorrow"]) {
      const response = await getDashboard(
        env,
        authFor("one"),
        new Request(`https://api.test/v1/dashboard?dayOffset=${dayOffset}`),
      );
      expect(response.status, dayOffset).toBe(400);
      expect(await response.json(), dayOffset).toEqual({ error: "Invalid dashboard day offset" });
    }
  });

  it("returns the selected prior day while leaving the report window current", async () => {
    const now = epoch("2026-09-03T12:00:00Z");
    await env.DB.batch([
      env.DB.prepare("INSERT INTO user_preferences (user_id, reporting_timezone) VALUES ('one', 'UTC')"),
      env.DB.prepare(
        `INSERT INTO sales
         (id, user_id, provider, provider_account_id, provider_event_id, provider_payment_id,
          amount_minor, currency, product_label, occurred_at)
         VALUES ('today', 'one', 'stripe', 'acct', 'today-event', 'today-payment',
                 300, 'USD', 'Today', ?1)`,
      ).bind(now - 1),
      env.DB.prepare(
        `INSERT INTO sales
         (id, user_id, provider, provider_account_id, provider_event_id, provider_payment_id,
          amount_minor, currency, product_label, occurred_at)
         VALUES ('yesterday', 'one', 'stripe', 'acct', 'yesterday-event', 'yesterday-payment',
                 200, 'USD', 'Yesterday', ?1)`,
      ).bind(epoch("2026-09-02T10:00:00Z")),
    ]);

    const response = await getDashboard(
      env,
      authFor("one"),
      new Request("https://api.test/v1/dashboard?period=1w&dayOffset=1"),
      now,
    );
    const body = await response.json<any>();
    expect(body.dayOffset).toBe(1);
    expect(body.today).toEqual(expect.objectContaining({
      start: "2026-09-02T00:00:00.000Z",
      end: "2026-09-03T00:00:00.000Z",
      payments: 1,
      currencies: [expect.objectContaining({ currency: "USD", grossAmountMinor: 200 })],
    }));
    expect(body.report.totals.payments.current).toBe(2);
  });

  it("aggregates every succeeded payment with currency, product, source, and zero-filled buckets", async () => {
    await env.DB.prepare(
      "INSERT INTO user_preferences (user_id, reporting_timezone) VALUES ('one', 'UTC')",
    ).run();
    await env.DB.prepare(
      `INSERT INTO custom_payment_sources
       (id, user_id, name, webhook_token_hash, webhook_token_ciphertext)
       VALUES ('custom-one', 'one', 'SERP Store', 'hash', 'ciphertext')`,
    ).run();
    const now = epoch("2026-09-03T12:00:00Z");
    const statements = [];
    for (let index = 0; index < 1_005; index += 1) {
      statements.push(env.DB.prepare(
        `INSERT INTO sales
         (id, user_id, provider, provider_account_id, provider_event_id, provider_payment_id,
          amount_minor, currency, status, product_label, occurred_at)
         VALUES (?1, 'one', ?2, ?3, ?4, ?5, ?6, ?7, 'succeeded', ?8, ?9)`,
      ).bind(
        `sale-${index}`,
        index % 2 === 0 ? "stripe" : "custom",
        index % 2 === 0 ? "acct" : "custom-one",
        `event-${index}`,
        `payment-${index}`,
        index === 1_004 ? 500 : 100,
        index === 1_004 ? "JPY" : "USD",
        index % 2 === 0 ? "Stripe payment" : "Widget",
        now - index - 1,
      ));
    }
    statements.push(env.DB.prepare(
      `INSERT INTO sales
       (id, user_id, provider, provider_account_id, provider_event_id, provider_payment_id,
        amount_minor, currency, status, product_label, occurred_at)
       VALUES ('refund', 'one', 'stripe', 'acct', 'refund-event', 'refund-payment',
               99999, 'USD', 'refunded', 'Refunded', ?1)`,
    ).bind(now - 30));
    for (let index = 0; index < statements.length; index += 75) {
      await env.DB.batch(statements.slice(index, index + 75));
    }
    const response = await getDashboard(
      env,
      authFor("one"),
      new Request("https://api.test/v1/dashboard?period=1w"),
      now,
    );
    const body = await response.json<any>();
    expect(body.today.payments).toBe(1_005);
    expect(body.report.totals.payments.current).toBe(1_005);
    expect(body.report.totals.currencies).toEqual(expect.arrayContaining([
      expect.objectContaining({ currency: "USD", currentAmountMinor: 100_400 }),
      expect.objectContaining({ currency: "JPY", currentAmountMinor: 500 }),
    ]));
    expect(body.report.products).toEqual(expect.arrayContaining([
      expect.objectContaining({
        label: "Stripe payment",
        amounts: expect.arrayContaining([
          expect.objectContaining({ currency: "USD", payments: 502 }),
          expect.objectContaining({ currency: "JPY", payments: 1 }),
        ]),
      }),
      expect.objectContaining({
        label: "Widget",
        amounts: [expect.objectContaining({ currency: "USD", payments: 502 })],
      }),
    ]));
    expect(body.report.sources).toEqual(expect.arrayContaining([
      expect.objectContaining({
        label: "Stripe",
        amounts: expect.arrayContaining([
          expect.objectContaining({ currency: "USD", payments: 502 }),
          expect.objectContaining({ currency: "JPY", payments: 1 }),
        ]),
      }),
      expect.objectContaining({
        label: "SERP Store",
        amounts: [expect.objectContaining({ currency: "USD", payments: 502 })],
      }),
    ]));
    expect(body.report.currentSeries).toHaveLength(7);
    expect(body.report.currentSeries[0]).toEqual(expect.objectContaining({ payments: 0 }));
    expect(body.report.currentSeries[0].amounts).toEqual([
      expect.objectContaining({ currency: "JPY", grossAmountMinor: 0 }),
      expect.objectContaining({ currency: "USD", grossAmountMinor: 0 }),
    ]);
    const allResponse = await getDashboard(
      env,
      authFor("one"),
      new Request("https://api.test/v1/dashboard?period=all"),
      now,
    );
    const allBody = await allResponse.json<any>();
    expect(allBody.report.previous).toBeNull();
    expect(allBody.report.totals.payments.comparison).toBeNull();
    expect(allBody.report.totals.currencies.every(
      (value: { comparison: unknown }) => value.comparison === null,
    )).toBe(true);
  }, 15_000);

  it("aggregates one transactional D1 batch across mutation boundaries", async () => {
    const now = epoch("2026-09-03T12:00:00Z");
    await env.DB.batch([
      env.DB.prepare("INSERT INTO user_preferences (user_id, reporting_timezone) VALUES ('one', 'UTC')"),
      env.DB.prepare(
        `INSERT INTO sales
         (id, user_id, provider, provider_account_id, provider_event_id, provider_payment_id,
          amount_minor, currency, product_label, occurred_at)
         VALUES ('before', 'one', 'stripe', 'acct', 'before-event', 'before-payment',
                 100, 'USD', 'Before', ?1)`,
      ).bind(now - 2),
    ]);
    const db = env.DB;
    let dashboardBatchCalls = 0;
    const transactionalDB = {
      prepare: db.prepare.bind(db),
      batch: async (statements: D1PreparedStatement[]) => {
        dashboardBatchCalls += 1;
        expect(statements).toHaveLength(11);
        await db.prepare(
          `INSERT INTO sales
           (id, user_id, provider, provider_account_id, provider_event_id, provider_payment_id,
            amount_minor, currency, product_label, occurred_at)
           VALUES ('at-boundary', 'one', 'stripe', 'acct', 'boundary-event', 'boundary-payment',
                   200, 'USD', 'Boundary', ?1)`,
        ).bind(now - 1).run();
        const result = await db.batch(statements);
        await db.prepare("DELETE FROM sales WHERE user_id = 'one'").run();
        return result;
      },
    } as unknown as D1Database;
    const response = await getDashboard(
      { ...env, DB: transactionalDB },
      authFor("one"),
      new Request("https://api.test/v1/dashboard?period=1w"),
      now,
    );
    const body = await response.json<any>();

    expect(dashboardBatchCalls).toBe(1);
    expect(body.today.payments).toBe(2);
    expect(body.report.totals.payments.current).toBe(2);
    expect(body.report.totals.currencies).toEqual([
      expect.objectContaining({ currency: "USD", currentAmountMinor: 300 }),
    ]);
    expect(body.report.currentSeries.reduce(
      (total: number, bucket: { payments: number }) => total + bucket.payments,
      0,
    )).toBe(2);
    expect(body.report.products.map((value: { label: string }) => value.label).sort())
      .toEqual(["Before", "Boundary"]);
    expect(await db.prepare("SELECT COUNT(*) AS count FROM sales WHERE user_id = 'one'")
      .first<{ count: number }>()).toEqual({ count: 0 });
  });

  it("rebuilds All boundaries when the transactional earliest row changes", async () => {
    const now = epoch("2026-09-03T12:00:00Z");
    const original = now - 10 * 86_400;
    const earlier = now - 400 * 86_400;
    await env.DB.batch([
      env.DB.prepare("INSERT INTO user_preferences (user_id, reporting_timezone) VALUES ('one', 'UTC')"),
      env.DB.prepare(
        `INSERT INTO sales
         (id, user_id, provider, provider_account_id, provider_event_id, provider_payment_id,
          amount_minor, currency, product_label, occurred_at)
         VALUES ('original', 'one', 'stripe', 'acct', 'original-event', 'original-payment',
                 100, 'USD', 'Original', ?1)`,
      ).bind(original),
    ]);
    const db = env.DB;
    let batchCalls = 0;
    const changingDB = {
      prepare: db.prepare.bind(db),
      batch: async (statements: D1PreparedStatement[]) => {
        batchCalls += 1;
        if (batchCalls === 1) {
          await db.prepare(
            `INSERT INTO sales
             (id, user_id, provider, provider_account_id, provider_event_id, provider_payment_id,
              amount_minor, currency, product_label, occurred_at)
             VALUES ('earlier', 'one', 'stripe', 'acct', 'earlier-event', 'earlier-payment',
                     200, 'USD', 'Earlier', ?1)`,
          ).bind(earlier).run();
        }
        return db.batch(statements);
      },
    } as unknown as D1Database;

    const response = await getDashboard(
      { ...env, DB: changingDB },
      authFor("one"),
      new Request("https://api.test/v1/dashboard?period=all"),
      now,
    );
    const body = await response.json<any>();
    expect(batchCalls).toBe(2);
    expect(body.report.current.start).toBe(new Date(earlier * 1_000).toISOString());
    expect(body.report.totals.payments.current).toBe(2);
    expect(body.report.currentSeries.reduce(
      (total: number, bucket: { payments: number }) => total + bucket.payments,
      0,
    )).toBe(2);
  });

  it("uses an honest fallback for a custom payment whose source was deleted", async () => {
    const now = epoch("2026-09-03T12:00:00Z");
    await env.DB.batch([
      env.DB.prepare("INSERT INTO user_preferences (user_id, reporting_timezone) VALUES ('two', 'UTC')"),
      env.DB.prepare(
        `INSERT INTO sales
         (id, user_id, provider, provider_account_id, provider_event_id, provider_payment_id,
          amount_minor, currency, product_label, occurred_at)
         VALUES ('orphaned-source', 'two', 'custom', 'deleted-source', 'orphan-event',
                 'orphan-payment', 500, 'USD', 'Widget', ?1)`,
      ).bind(now - 1),
    ]);

    const response = await getDashboard(
      env,
      authFor("two"),
      new Request("https://api.test/v1/dashboard?period=1w"),
      now,
    );
    const body = await response.json<any>();
    expect(body.report.sources).toEqual([expect.objectContaining({ label: "Custom webhook" })]);
    expect(body.report.products).toEqual([expect.objectContaining({ label: "Widget" })]);
  });

  it("returns adaptive day, month, and year bucket shapes for All", async () => {
    const now = epoch("2026-09-03T12:00:00Z");
    const cases = [
      { user: "span-day", earliest: now - 10 * 86_400, range: [10, 12] },
      { user: "span-month", earliest: now - 400 * 86_400, range: [13, 15] },
      { user: "span-year", earliest: now - 4 * 365 * 86_400, range: [4, 6] },
    ];
    for (const item of cases) {
      await env.DB.batch([
        env.DB.prepare(
          "INSERT INTO user (id, name, email, created_at, updated_at) VALUES (?1, 'Founder', ?2, ?3, ?3)",
        ).bind(item.user, `${item.user}@example.test`, Date.now()),
        env.DB.prepare(
          "INSERT INTO user_preferences (user_id, reporting_timezone) VALUES (?1, 'UTC')",
        ).bind(item.user),
      ]);
      await env.DB.batch([item.earliest, now - 1].map((occurredAt, index) => env.DB.prepare(
        `INSERT INTO sales
         (id, user_id, provider, provider_account_id, provider_event_id, provider_payment_id,
          amount_minor, currency, product_label, occurred_at)
         VALUES (?1, ?2, 'stripe', 'acct', ?3, ?4, 100, 'USD', 'Payment', ?5)`,
      ).bind(
        `${item.user}-${index}`,
        item.user,
        `${item.user}-event-${index}`,
        `${item.user}-payment-${index}`,
        occurredAt,
      )));

      const response = await getDashboard(
        env,
        authFor(item.user),
        new Request("https://api.test/v1/dashboard?period=all"),
        now,
      );
      const body = await response.json<any>();
      const series = body.report.currentSeries as Array<{ start: string; end: string; payments: number }>;
      expect(series.length, item.user).toBeGreaterThanOrEqual(item.range[0]);
      expect(series.length, item.user).toBeLessThanOrEqual(item.range[1]);
      expect(series[0].start, item.user).toBe(new Date(item.earliest * 1_000).toISOString());
      expect(series.at(-1)?.end, item.user).toBe(new Date(now * 1_000).toISOString());
      expect(series.reduce((total, bucket) => total + bucket.payments, 0), item.user).toBe(2);
      for (let index = 1; index < series.length; index += 1) {
        expect(series[index - 1].end, item.user).toBe(series[index].start);
      }
    }
  }, 15_000);
});
