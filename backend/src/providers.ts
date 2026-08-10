import type { Env, Provider } from "./env";

export interface ProviderTokens {
  providerAccountId: string;
  accountLabel: string | null;
  accessToken: string;
  refreshToken: string | null;
  expiresAt: string | null;
  scope: string | null;
}

export function callbackURL(env: Env, provider: Provider): string {
  return `${env.PUBLIC_BASE_URL}/v1/oauth/${provider}/callback`;
}

export function authorizationURL(env: Env, provider: Provider, state: string): string {
  const redirectUri = callbackURL(env, provider);
  if (provider === "stripe") {
    if (!env.STRIPE_CONNECT_CLIENT_ID) throw new Error("Stripe Connect is not configured");
    const url = new URL("https://connect.stripe.com/oauth/authorize");
    url.searchParams.set("response_type", "code");
    url.searchParams.set("client_id", env.STRIPE_CONNECT_CLIENT_ID);
    url.searchParams.set("scope", "read_write");
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

async function exchangeStripe(env: Env, code: string): Promise<ProviderTokens> {
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    client_secret: env.STRIPE_SECRET_KEY,
  });
  const response = await fetch("https://connect.stripe.com/oauth/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body,
  });
  const payload = (await response.json()) as {
    access_token?: string;
    refresh_token?: string;
    stripe_user_id?: string;
    scope?: string;
    error_description?: string;
  };
  if (!response.ok || !payload.access_token || !payload.stripe_user_id) {
    throw new Error(payload.error_description ?? "Stripe rejected the authorization code");
  }

  const accountResponse = await fetch("https://api.stripe.com/v1/account", {
    headers: { authorization: `Bearer ${payload.access_token}` },
  });
  const account = accountResponse.ok
    ? ((await accountResponse.json()) as {
        business_profile?: { name?: string };
        business_name?: string;
        email?: string;
      })
    : null;
  return {
    providerAccountId: payload.stripe_user_id,
    accountLabel:
      account?.business_profile?.name ?? account?.business_name ?? account?.email ?? payload.stripe_user_id,
    accessToken: payload.access_token,
    refreshToken: payload.refresh_token ?? null,
    expiresAt: null,
    scope: payload.scope ?? null,
  };
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
  return provider === "stripe" ? exchangeStripe(env, code) : exchangePayPal(env, code);
}

export async function deauthorizeStripe(
  env: Env,
  stripeAccountId: string,
): Promise<void> {
  const response = await fetch("https://connect.stripe.com/oauth/deauthorize", {
    method: "POST",
    headers: {
      authorization: `Basic ${btoa(`${env.STRIPE_SECRET_KEY}:`)}`,
      "content-type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      client_id: env.STRIPE_CONNECT_CLIENT_ID,
      stripe_user_id: stripeAccountId,
    }),
  });
  if (!response.ok) throw new Error("Stripe could not revoke the connection");
}
