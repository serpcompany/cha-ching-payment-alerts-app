import type { Env, Provider } from "./env";
import { verifyStripeSignature } from "./stripe-webhooks";

export interface ProviderAuthorizationEnv {
  PUBLIC_BASE_URL: string;
  STRIPE_APP_INSTALL_URL: string;
  PAYPAL_CLIENT_ID: string;
  PAYPAL_ENVIRONMENT: "sandbox" | "live";
}

export interface ProviderTokens {
  providerAccountId: string;
  accountLabel: string | null;
  accessToken: string | null;
  refreshToken: string | null;
  expiresAt: string | null;
  scope: string | null;
}

export function providerConnectionFailureMessage(provider: Provider, error: unknown): string {
  void error;
  return `Couldn't connect ${provider}`;
}

export function callbackURL(env: Pick<ProviderAuthorizationEnv, "PUBLIC_BASE_URL">, provider: Provider): string {
  return `${env.PUBLIC_BASE_URL}/v1/oauth/${provider}/callback`;
}

export function authorizationURL(env: ProviderAuthorizationEnv, provider: Provider, state: string): string {
  const redirectUri = callbackURL(env, provider);
  if (provider === "stripe") {
    if (!env.STRIPE_APP_INSTALL_URL) throw new Error("Stripe App is not configured");
    const url = new URL(env.STRIPE_APP_INSTALL_URL);
    url.searchParams.set("redirect_uri", redirectUri);
    url.searchParams.set("state", state);
    return url.toString();
  }

  if (!env.PAYPAL_CLIENT_ID) throw new Error("PayPal is not configured");
  const host = env.PAYPAL_ENVIRONMENT === "live" ? "www.paypal.com" : "www.sandbox.paypal.com";
  const url = new URL(`https://${host}/signin/authorize`);
  url.searchParams.set("flowEntry", "static");
  url.searchParams.set("client_id", env.PAYPAL_CLIENT_ID);
  url.searchParams.set("response_type", "code");
  url.searchParams.set(
    "scope",
    "openid profile email https://uri.paypal.com/services/paypalattributes",
  );
  url.searchParams.set("redirect_uri", redirectUri);
  url.searchParams.set("state", state);
  return url.toString();
}

export async function verifyStripeAppInstall(
  env: Pick<Env, "STRIPE_APP_SIGNING_SECRET">,
  install: { state: string; stripeUserId: string; accountId: string; signature: string },
  nowSeconds = Math.floor(Date.now() / 1_000),
): Promise<ProviderTokens> {
  const payload = JSON.stringify({
    state: install.state,
    user_id: install.stripeUserId,
    account_id: install.accountId,
  });
  if (!/^acct_[A-Za-z0-9]+$/.test(install.accountId) || !install.stripeUserId || !install.signature) {
    throw new Error("Stripe returned an invalid app installation callback");
  }
  const verified = await verifyStripeSignature(
    payload,
    install.signature,
    env.STRIPE_APP_SIGNING_SECRET,
    nowSeconds,
  );
  if (!verified) throw new Error("Stripe returned an invalid app installation signature");
  return {
    providerAccountId: install.accountId,
    accountLabel: install.accountId,
    accessToken: null,
    refreshToken: null,
    expiresAt: null,
    scope: "event_read charge_read",
  };
}

export async function verifyStripeAccountMode(
  env: Pick<Env, "ENVIRONMENT" | "STRIPE_SECRET_KEY">,
  accountId: string,
): Promise<void> {
  if (env.ENVIRONMENT !== "production") return;
  if (!env.STRIPE_SECRET_KEY) throw new Error("Stripe live account verification is unavailable");

  const response = await fetch("https://api.stripe.com/v1/charges?limit=1", {
    headers: {
      authorization: `Bearer ${env.STRIPE_SECRET_KEY}`,
      "stripe-account": accountId,
    },
  });
  if (!response.ok) {
    throw new Error("Stripe account is not available in live mode");
  }
}

function paypalAPIBase(env: Env): string {
  return env.PAYPAL_ENVIRONMENT === "live"
    ? "https://api-m.paypal.com"
    : "https://api-m.sandbox.paypal.com";
}

async function exchangePayPal(env: Env, code: string): Promise<ProviderTokens> {
  const credentials = btoa(`${env.PAYPAL_CLIENT_ID}:${env.PAYPAL_CLIENT_SECRET}`);
  const response = await fetch(`${paypalAPIBase(env)}/v1/oauth2/token`, {
    method: "POST",
    headers: {
      authorization: `Basic ${credentials}`,
      "content-type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({ grant_type: "authorization_code", code }),
  });
  const payload = (await response.json()) as {
    access_token?: string;
    refresh_token?: string;
    expires_in?: number;
    scope?: string;
    error_description?: string;
  };
  if (!response.ok || !payload.access_token) {
    throw new Error(payload.error_description ?? "PayPal rejected the authorization code");
  }

  const profileResponse = await fetch(
    `${paypalAPIBase(env)}/v1/identity/oauth2/userinfo?schema=paypalv1.1`,
    { headers: { authorization: `Bearer ${payload.access_token}` } },
  );
  const profile = (await profileResponse.json()) as {
    payer_id?: string;
    user_id?: string;
    email?: string;
    name?: string;
  };
  const accountId = profile.payer_id ?? profile.user_id;
  if (!profileResponse.ok || !accountId) throw new Error("PayPal did not return an account ID");

  return {
    providerAccountId: accountId,
    accountLabel: profile.email ?? profile.name ?? accountId,
    accessToken: payload.access_token,
    refreshToken: payload.refresh_token ?? null,
    expiresAt: payload.expires_in
      ? new Date(Date.now() + payload.expires_in * 1_000).toISOString()
      : null,
    scope: payload.scope ?? null,
  };
}

export function exchangeAuthorizationCode(env: Env, provider: Provider, code: string) {
  if (provider === "stripe") throw new Error("Stripe uses the Stripe App installation callback");
  return exchangePayPal(env, code);
}
