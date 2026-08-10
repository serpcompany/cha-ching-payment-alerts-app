import type { Auth } from "./auth";
import { requireUser } from "./auth";
import { encryptSecret, randomToken, sha256 } from "./crypto";
import { requireProviderEntitlement } from "./entitlements";
import type { Env, Provider } from "./env";
import {
  authorizationURL,
  deauthorizeStripe,
  exchangeAuthorizationCode,
} from "./providers";

interface ConnectionRow {
  provider: Provider;
  status: "connected" | "revoked" | "error";
  provider_account_id: string;
  account_label: string | null;
  updated_at: string;
}

function parseProvider(value: string): Provider | null {
  return value === "stripe" || value === "paypal" ? value : null;
}

export async function listConnections(env: Env, auth: Auth, request: Request): Promise<Response> {
  const user = await requireUser(auth, request);
  const result = await env.DB.prepare(
    "SELECT provider, status, provider_account_id, account_label, updated_at FROM provider_connections WHERE user_id = ?1 ORDER BY provider",
  )
    .bind(user.id)
    .all<ConnectionRow>();
  return Response.json({
    connections: result.results.map((row) => ({
      provider: row.provider,
      status: row.status,
      providerAccountId: row.provider_account_id,
      accountLabel: row.account_label,
      updatedAt: row.updated_at,
    })),
  });
}

export async function beginConnection(
  env: Env,
  auth: Auth,
  request: Request,
  providerValue: string,
): Promise<Response> {
  const provider = parseProvider(providerValue);
  if (!provider) return Response.json({ error: "Unsupported provider" }, { status: 400 });
  const user = await requireUser(auth, request);
  await requireProviderEntitlement(env.DB, user.id, provider);

  const state = randomToken();
  const stateHash = await sha256(state);
  const expiresAt = new Date(Date.now() + 10 * 60 * 1_000).toISOString();
  await env.DB.prepare(
    "INSERT INTO oauth_states (state_hash, user_id, provider, expires_at) VALUES (?1, ?2, ?3, ?4)",
  )
    .bind(stateHash, user.id, provider, expiresAt)
    .run();
  return Response.json({ authorizationUrl: authorizationURL(env, provider, state) });
}

function appRedirect(provider: Provider, status: "connected" | "error", message?: string) {
  const url = new URL("chaching://oauth-callback");
  url.searchParams.set("provider", provider);
  url.searchParams.set("status", status);
  if (message) url.searchParams.set("message", message);
  return new Response(null, { status: 302, headers: { location: url.toString() } });
}

export async function completeConnection(
  env: Env,
  request: Request,
  providerValue: string,
): Promise<Response> {
  const provider = parseProvider(providerValue);
  if (!provider) return Response.json({ error: "Unsupported provider" }, { status: 400 });
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  if (url.searchParams.has("error")) return appRedirect(provider, "error", "Authorization cancelled");
  if (!code || !state) return appRedirect(provider, "error", "Invalid authorization response");

  const stateHash = await sha256(state);
  const consumed = await env.DB.prepare(
    "DELETE FROM oauth_states WHERE state_hash = ?1 AND provider = ?2 AND expires_at > ?3 RETURNING user_id",
  )
    .bind(stateHash, provider, new Date().toISOString())
    .first<{ user_id: string }>();
  if (!consumed) return appRedirect(provider, "error", "This connection request expired");

  try {
    await requireProviderEntitlement(env.DB, consumed.user_id, provider);
    const tokens = await exchangeAuthorizationCode(env, provider, code);
    const [accessToken, refreshToken] = await Promise.all([
      encryptSecret(tokens.accessToken, env.PROVIDER_TOKEN_ENCRYPTION_KEY),
      tokens.refreshToken
        ? encryptSecret(tokens.refreshToken, env.PROVIDER_TOKEN_ENCRYPTION_KEY)
        : Promise.resolve(null),
    ]);
    await env.DB.prepare(
      `INSERT INTO provider_connections (
        id, user_id, provider, status, provider_account_id, account_label,
        access_token_ciphertext, refresh_token_ciphertext, token_expires_at, scope
      ) VALUES (?1, ?2, ?3, 'connected', ?4, ?5, ?6, ?7, ?8, ?9)
      ON CONFLICT(user_id, provider) DO UPDATE SET
        status = 'connected', provider_account_id = excluded.provider_account_id,
        account_label = excluded.account_label,
        access_token_ciphertext = excluded.access_token_ciphertext,
        refresh_token_ciphertext = excluded.refresh_token_ciphertext,
        token_expires_at = excluded.token_expires_at, scope = excluded.scope,
        updated_at = CURRENT_TIMESTAMP`,
    )
      .bind(
        crypto.randomUUID(),
        consumed.user_id,
        provider,
        tokens.providerAccountId,
        tokens.accountLabel,
        accessToken,
        refreshToken,
        tokens.expiresAt,
        tokens.scope,
      )
      .run();
    return appRedirect(provider, "connected");
  } catch (error) {
    console.error("oauth.connection.failed", {
      provider,
      message: error instanceof Error ? error.message : "Unknown error",
    });
    return appRedirect(provider, "error", `Couldn't connect ${provider}`);
  }
}

export async function disconnect(
  env: Env,
  auth: Auth,
  request: Request,
  providerValue: string,
): Promise<Response> {
  const provider = parseProvider(providerValue);
  if (!provider) return Response.json({ error: "Unsupported provider" }, { status: 400 });
  const user = await requireUser(auth, request);
  const connection = await env.DB.prepare(
    "SELECT provider_account_id FROM provider_connections WHERE user_id = ?1 AND provider = ?2",
  )
    .bind(user.id, provider)
    .first<{ provider_account_id: string }>();
  if (!connection) return new Response(null, { status: 204 });
  if (provider === "stripe") await deauthorizeStripe(env, connection.provider_account_id);
  await env.DB.prepare("DELETE FROM provider_connections WHERE user_id = ?1 AND provider = ?2")
    .bind(user.id, provider)
    .run();
  return new Response(null, { status: 204 });
}
