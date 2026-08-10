export type Provider = "stripe" | "paypal";

interface SecretBindings {
  BETTER_AUTH_SECRET: string;
  APPLE_TEAM_ID: string;
  APPLE_KEY_ID: string;
  APPLE_PRIVATE_KEY: string;
  APNS_KEY_ID: string;
  APNS_PRIVATE_KEY: string;
  PROVIDER_TOKEN_ENCRYPTION_KEY: string;
  STRIPE_SECRET_KEY: string;
  STRIPE_APP_INSTALL_URL: string;
  STRIPE_APP_SIGNING_SECRET: string;
  STRIPE_WEBHOOK_SECRET: string;
  PAYPAL_CLIENT_ID: string;
  PAYPAL_CLIENT_SECRET: string;
}

interface RuntimeOverrides {
  ENVIRONMENT: "development" | "staging" | "production";
  PUBLIC_BASE_URL: string;
  PAYPAL_ENVIRONMENT: "sandbox" | "live";
}

export type Env = Omit<Cloudflare.Env, keyof RuntimeOverrides> & RuntimeOverrides & SecretBindings;

export function isAppleConfigured(env: Env): boolean {
  return Boolean(
    env.APPLE_TEAM_ID
      && env.APPLE_KEY_ID
      && env.APPLE_PRIVATE_KEY
      && env.APPLE_SERVICE_ID
      && env.APPLE_APP_BUNDLE_ID,
  );
}

/**
 * The passwordless Simulator session is deliberately limited to the local
 * development environment. Staging and production never register its route.
 */
export function isSimulatorAuthEnabled(
  env: Pick<Env, "ENVIRONMENT" | "PUBLIC_BASE_URL">,
): boolean {
  if (env.ENVIRONMENT !== "development") return false;
  try {
    const hostname = new URL(env.PUBLIC_BASE_URL).hostname;
    return hostname === "127.0.0.1" || hostname === "localhost" || hostname === "[::1]";
  } catch {
    return false;
  }
}

export function isSimulatorAuthRequestAllowed(
  env: Pick<Env, "ENVIRONMENT" | "PUBLIC_BASE_URL">,
  requestURL: string,
): boolean {
  if (!isSimulatorAuthEnabled(env)) return false;
  try {
    const hostname = new URL(requestURL).hostname;
    return hostname === "127.0.0.1" || hostname === "localhost" || hostname === "[::1]";
  } catch {
    return false;
  }
}

export function missingCoreConfiguration(env: Env): string[] {
  const required: Array<keyof SecretBindings> = [
    "BETTER_AUTH_SECRET",
    "PROVIDER_TOKEN_ENCRYPTION_KEY",
  ];
  if (!isSimulatorAuthEnabled(env)) {
    required.push("APPLE_TEAM_ID", "APPLE_KEY_ID", "APPLE_PRIVATE_KEY");
  }
  return required.filter((key) => !env[key]);
}

export function assertConfigured(env: Env): void {
  const missing = missingCoreConfiguration(env);
  if (missing.length > 0) {
    throw new Error(`Missing required configuration: ${missing.join(", ")}`);
  }
}

export function isStripeConfigured(env: Env): boolean {
  if (!env.STRIPE_SECRET_KEY || !env.STRIPE_APP_SIGNING_SECRET) return false;
  try {
    const url = new URL(env.STRIPE_APP_INSTALL_URL);
    const isPublishedInstall = url.hostname === "marketplace.stripe.com"
      && url.pathname.startsWith("/apps/");
    const isExternalTestInstall = url.hostname === "dashboard.stripe.com"
      && url.pathname.startsWith("/apps/install/link/");
    return url.protocol === "https:"
      && url.port === ""
      && url.username === ""
      && url.password === ""
      && (isPublishedInstall || isExternalTestInstall);
  } catch {
    return false;
  }
}

export function isPayPalConfigured(env: Env): boolean {
  return Boolean(env.PAYPAL_CLIENT_ID && env.PAYPAL_CLIENT_SECRET);
}

export function isPushConfigured(env: Env): boolean {
  return Boolean(env.APNS_KEY_ID && env.APNS_PRIVATE_KEY && env.APPLE_TEAM_ID);
}

export function providerCapabilities(env: Env) {
  return {
    stripe: isStripeConfigured(env),
    paypal: isPayPalConfigured(env),
  };
}
