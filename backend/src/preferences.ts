import type { Auth } from "./auth";
import { requireUser } from "./auth";
import type { Env } from "./env";

interface PreferenceBody {
  reportingTimezone?: unknown;
  initializeOnly?: unknown;
}
export function isValidTimeZone(identifier: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: identifier }).format();
    return true;
  } catch {
    return false;
  }
}

async function readBody(request: Request): Promise<PreferenceBody> {
  try {
    return await request.json<PreferenceBody>();
  } catch {
    throw Response.json({ error: "Invalid JSON body" }, { status: 400 });
  }
}

export async function getPreferences(env: Env, auth: Auth, request: Request): Promise<Response> {
  const user = await requireUser(auth, request);
  const row = await env.DB.prepare(
    "SELECT reporting_timezone FROM user_preferences WHERE user_id = ?1",
  ).bind(user.id).first<{ reporting_timezone: string }>();
  return Response.json({ reportingTimezone: row?.reporting_timezone ?? null });
}

export async function updatePreferences(env: Env, auth: Auth, request: Request): Promise<Response> {
  const user = await requireUser(auth, request);
  const body = await readBody(request);
  if (typeof body.reportingTimezone !== "string" || !isValidTimeZone(body.reportingTimezone)) {
    return Response.json({ error: "Invalid reporting timezone" }, { status: 400 });
  }
  if (body.initializeOnly !== undefined && typeof body.initializeOnly !== "boolean") {
    return Response.json({ error: "initializeOnly must be a boolean" }, { status: 400 });
  }

  if (body.initializeOnly === true) {
    await env.DB.prepare(
      `INSERT OR IGNORE INTO user_preferences (user_id, reporting_timezone)
       VALUES (?1, ?2)`,
    ).bind(user.id, body.reportingTimezone).run();
  } else {
    await env.DB.prepare(
      `INSERT INTO user_preferences (user_id, reporting_timezone)
       VALUES (?1, ?2)
       ON CONFLICT(user_id) DO UPDATE SET
         reporting_timezone = excluded.reporting_timezone,
         updated_at = CURRENT_TIMESTAMP`,
    ).bind(user.id, body.reportingTimezone).run();
  }

  const saved = await env.DB.prepare(
    "SELECT reporting_timezone FROM user_preferences WHERE user_id = ?1",
  ).bind(user.id).first<{ reporting_timezone: string }>();
  return Response.json({ reportingTimezone: saved?.reporting_timezone });
}
