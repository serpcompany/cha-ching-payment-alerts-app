import { decodeJwt } from "jose";

import { appleClientSecret, requireUser } from "./auth";
import type { Auth } from "./auth";
import { decryptSecret, encryptSecret, sha256 } from "./crypto";
import type { Env } from "./env";

interface AppleTokenResponse {
  access_token?: string;
  expires_in?: number;
  id_token?: string;
  refresh_token?: string;
  token_type?: string;
  error?: string;
  error_description?: string;
}

export interface AppleCredentialClient {
  exchangeAuthorizationCode(code: string, nonce: string): Promise<{
    subject: string;
    refreshToken: string;
  }>;
  revokeRefreshToken(refreshToken: string): Promise<void>;
}

function formBody(values: Record<string, string>): string {
  return new URLSearchParams(values).toString();
}

export function appleCredentialClient(env: Env): AppleCredentialClient {
  const clientId = env.APPLE_APP_BUNDLE_ID;
  return {
    async exchangeAuthorizationCode(code, nonce) {
      const response = await fetch("https://appleid.apple.com/auth/token", {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: formBody({
          client_id: clientId,
          client_secret: await appleClientSecret(env, clientId),
          code,
          grant_type: "authorization_code",
        }),
      });
      const payload = await response.json<AppleTokenResponse>();
      if (!response.ok || !payload.refresh_token || !payload.id_token) {
        throw new Error(payload.error_description ?? payload.error ?? "Apple authorization code exchange failed");
      }
      const claims = decodeJwt(payload.id_token);
      const audience = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
      if (
        claims.iss !== "https://appleid.apple.com"
        || !audience.includes(clientId)
        || !claims.sub
        || claims.nonce !== await sha256(nonce)
      ) {
        throw new Error("Apple returned an invalid identity token");
      }
      return { subject: claims.sub, refreshToken: payload.refresh_token };
    },
    async revokeRefreshToken(refreshToken) {
      const response = await fetch("https://appleid.apple.com/auth/revoke", {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: formBody({
          client_id: clientId,
          client_secret: await appleClientSecret(env, clientId),
          token: refreshToken,
          token_type_hint: "refresh_token",
        }),
      });
      if (!response.ok) {
        const payload: AppleTokenResponse = await response.json<AppleTokenResponse>().catch(() => ({}));
        throw new Error(payload.error_description ?? payload.error ?? "Apple credential revocation failed");
      }
    },
  };
}

function requestError(status: number, error: string): Response {
  return Response.json({ error }, { status });
}

export async function handleAppleCredentialRequest(
  env: Env,
  auth: Auth,
  request: Request,
  client: AppleCredentialClient = appleCredentialClient(env),
): Promise<Response> {
  if (request.method !== "POST") return requestError(405, "Method not allowed");
  const user = await requireUser(auth, request);
  const body: { authorizationCode?: unknown; nonce?: unknown } = await request
    .json<{ authorizationCode?: unknown; nonce?: unknown }>()
    .catch(() => ({}));
  if (typeof body.authorizationCode !== "string" || body.authorizationCode.length === 0) {
    return requestError(400, "Apple authorization code is required");
  }
  if (typeof body.nonce !== "string" || body.nonce.length === 0) {
    return requestError(400, "Apple authorization nonce is required");
  }
  const account = await env.DB.prepare(
    "SELECT account_id FROM account WHERE user_id = ?1 AND provider_id = 'apple'",
  ).bind(user.id).first<{ account_id: string }>();
  if (!account) return requestError(409, "No linked Sign in with Apple account was found");

  let exchanged: Awaited<ReturnType<AppleCredentialClient["exchangeAuthorizationCode"]>>;
  try {
    exchanged = await client.exchangeAuthorizationCode(body.authorizationCode, body.nonce);
  } catch (error) {
    console.error(JSON.stringify({
      message: "apple.authorization-code.exchange-failed",
      userId: user.id,
      error: error instanceof Error ? error.message : "Unknown error",
    }));
    return requestError(502, "Cha-Ching couldn't secure the Apple credential needed for account deletion");
  }
  if (exchanged.subject !== account.account_id) {
    return requestError(403, "Apple authorization does not match the signed-in account");
  }
  const ciphertext = await encryptSecret(exchanged.refreshToken, env.PROVIDER_TOKEN_ENCRYPTION_KEY);
  await env.DB.prepare(
    `INSERT INTO apple_account_credentials
       (user_id, apple_subject, client_id, refresh_token_ciphertext)
     VALUES (?1, ?2, ?3, ?4)
     ON CONFLICT(user_id) DO UPDATE SET
       apple_subject = excluded.apple_subject,
       client_id = excluded.client_id,
       refresh_token_ciphertext = excluded.refresh_token_ciphertext,
       updated_at = CURRENT_TIMESTAMP`,
  ).bind(user.id, exchanged.subject, env.APPLE_APP_BUNDLE_ID, ciphertext).run();
  return Response.json({ stored: true });
}

export async function handleAccountDeletion(
  env: Env,
  auth: Auth,
  request: Request,
  client: AppleCredentialClient = appleCredentialClient(env),
): Promise<Response> {
  if (request.method !== "DELETE") return requestError(405, "Method not allowed");
  const user = await requireUser(auth, request);
  const credential = await env.DB.prepare(
    "SELECT refresh_token_ciphertext FROM apple_account_credentials WHERE user_id = ?1",
  ).bind(user.id).first<{ refresh_token_ciphertext: string }>();

  let appleCredentialRevoked = false;
  if (credential) {
    try {
      const refreshToken = await decryptSecret(
        credential.refresh_token_ciphertext,
        env.PROVIDER_TOKEN_ENCRYPTION_KEY,
      );
      await client.revokeRefreshToken(refreshToken);
      appleCredentialRevoked = true;
    } catch (error) {
      console.error(JSON.stringify({
        message: "apple.credential.revoke-failed",
        userId: user.id,
        error: error instanceof Error ? error.message : "Unknown error",
      }));
      return requestError(502, "Apple sign-in access couldn't be revoked. Your account was not deleted; please try again.");
    }
  }

  await env.DB.batch([
    // These audit rows intentionally use ON DELETE SET NULL for unmatched
    // webhook deduplication. Explicit deletion prevents provider account IDs
    // from surviving an authenticated full-account deletion.
    env.DB.prepare("DELETE FROM provider_events WHERE user_id = ?1").bind(user.id),
    env.DB.prepare("DELETE FROM user WHERE id = ?1").bind(user.id),
  ]);
  return Response.json({ deleted: true, appleCredentialRevoked });
}
