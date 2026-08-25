import { readFile } from "node:fs/promises";
import { join } from "node:path";

import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { createAuth } from "../src/auth";
import type { Env } from "../src/env";

const DAY_MS = 24 * 60 * 60 * 1_000;
const YEAR_MS = 365 * DAY_MS;

describe("Better Auth mobile session policy", () => {
  let miniflare: Miniflare;
  let env: Env;

  beforeEach(async () => {
    miniflare = new Miniflare({
      modules: true,
      script: "export default { fetch() { return new Response('ok') } }",
      d1Databases: ["DB"],
    });
    const db = await miniflare.getD1Database("DB");
    for (const migrationName of [
      "0001_initial.sql",
      "0003_anonymous_simulator_user.sql",
    ]) {
      const statements = (await readFile(
        join(process.cwd(), "migrations", migrationName),
        "utf8",
      ))
        .replace(/--.*$/gm, "")
        .split(";")
        .map((statement) => statement.trim())
        .filter((statement) => statement && !statement.startsWith("PRAGMA foreign_keys"));
      for (const statement of statements) await db.prepare(statement).run();
    }
    env = {
      DB: db,
      ENVIRONMENT: "development",
      PUBLIC_BASE_URL: "http://127.0.0.1:8787",
      BETTER_AUTH_SECRET: "test-only-secret-with-adequate-length-123456789",
    } as unknown as Env;
  });

  afterEach(async () => miniflare.dispose());

  it("keeps a newly created native session valid for one year", async () => {
    const response = await signInLocally(env);
    const session = await env.DB.prepare(
      "SELECT created_at, expires_at FROM session",
    ).first<{ created_at: number | string; expires_at: number | string }>();

    expect(response.status).toBe(200);
    expect(session).not.toBeNull();
    const lifetime = timestamp(session!.expires_at) - timestamp(session!.created_at);
    expect(lifetime).toBeGreaterThanOrEqual(YEAR_MS - 5_000);
    expect(lifetime).toBeLessThanOrEqual(YEAR_MS + 5_000);
  });

  it("extends an active session back to one year after the update interval", async () => {
    const signInResponse = await signInLocally(env);
    const bearerToken = signInResponse.headers.get("set-auth-token");
    expect(bearerToken).toBeTruthy();

    const beforeRefresh = Date.now();
    await env.DB.prepare(
      "UPDATE session SET expires_at = ?1, updated_at = ?2",
    ).bind(beforeRefresh + 363 * DAY_MS, beforeRefresh - 2 * DAY_MS).run();

    const response = await createAuth(env).handler(new Request(
      "http://127.0.0.1:8787/api/auth/get-session",
      { headers: { authorization: `Bearer ${bearerToken}` } },
    ));
    const session = await env.DB.prepare(
      "SELECT expires_at FROM session",
    ).first<{ expires_at: number | string }>();

    expect(response.status).toBe(200);
    expect(await response.json()).not.toBeNull();
    expect(session).not.toBeNull();
    expect(timestamp(session!.expires_at)).toBeGreaterThanOrEqual(beforeRefresh + YEAR_MS - 5_000);
  });
});

async function signInLocally(env: Env): Promise<Response> {
  return createAuth(env).handler(new Request(
    "http://127.0.0.1:8787/api/auth/sign-in/anonymous",
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "{}",
    },
  ));
}

function timestamp(value: number | string): number {
  return typeof value === "number" ? value : new Date(value).getTime();
}
