import type { Auth } from "./auth";
import { requireUser } from "./auth";
import type { Env } from "./env";

const DEVICE_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TOKEN_PATTERN = /^[0-9a-f]{32,256}$/i;

interface DeviceRegistration {
  deviceId: string;
  token: string;
  environment: "development" | "production";
}

function parseRegistration(value: unknown): DeviceRegistration | null {
  if (!value || typeof value !== "object") return null;
  const body = value as Record<string, unknown>;
  if (
    typeof body.deviceId !== "string" ||
    !DEVICE_ID_PATTERN.test(body.deviceId) ||
    typeof body.token !== "string" ||
    !TOKEN_PATTERN.test(body.token) ||
    (body.environment !== "development" && body.environment !== "production")
  ) {
    return null;
  }
  return {
    deviceId: body.deviceId.toLowerCase(),
    token: body.token.toLowerCase(),
    environment: body.environment,
  };
}

export async function registerDevice(env: Env, auth: Auth, request: Request): Promise<Response> {
  const user = await requireUser(auth, request);
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: "Invalid JSON" }, { status: 400 });
  }
  const registration = parseRegistration(body);
  if (!registration) return Response.json({ error: "Invalid device registration" }, { status: 400 });

  await env.DB.prepare("DELETE FROM device_tokens WHERE token = ?1 AND user_id != ?2")
    .bind(registration.token, user.id)
    .run();
  await env.DB.prepare(
    `INSERT INTO device_tokens (id, user_id, device_id, token, environment)
     VALUES (?1, ?2, ?3, ?4, ?5)
     ON CONFLICT(user_id, device_id) DO UPDATE SET
       token = excluded.token, environment = excluded.environment, status = 'active',
       last_seen_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP`,
  )
    .bind(crypto.randomUUID(), user.id, registration.deviceId, registration.token, registration.environment)
    .run();
  return Response.json({ registered: true });
}

export async function unregisterDevice(
  env: Env,
  auth: Auth,
  request: Request,
  deviceId: string,
): Promise<Response> {
  const user = await requireUser(auth, request);
  if (!DEVICE_ID_PATTERN.test(deviceId)) {
    return Response.json({ error: "Invalid device ID" }, { status: 400 });
  }
  await env.DB.prepare("DELETE FROM device_tokens WHERE user_id = ?1 AND device_id = ?2")
    .bind(user.id, deviceId.toLowerCase())
    .run();
  return new Response(null, { status: 204 });
}
