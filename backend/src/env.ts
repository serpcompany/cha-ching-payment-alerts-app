export type Provider = "stripe" | "paypal";

interface SecretBindings {
  BETTER_AUTH_SECRET: string;
  APPLE_TEAM_ID: string;
  APPLE_KEY_ID: string;
  APPLE_PRIVATE_KEY: string;
  APNS_KEY_ID: string;
  APNS_PRIVATE_KEY: string;
  PROVIDER_TOKEN_ENCRYPTION_KEY: string;
  STRIPE_CONNECT_CLIENT_ID: string;
  STRIPE_SECRET_KEY: string;
  STRIPE_WEBHOOK_SECRET: string;
  PAYPAL_CLIENT_ID: string;
  PAYPAL_CLIENT_SECRET: string;
}

interface RuntimeOverrides {
  ENVIRONMENT: "development" | "staging" | "production";
  PAYPAL_ENVIRONMENT: "sandbox" | "live";
}

export type Env = Omit<Cloudflare.Env, keyof RuntimeOverrides> & RuntimeOverrides & SecretBindings;

export function missingCoreConfiguration(env: Env): string[] {
  const required: Array<keyof SecretBindings> = [
    "BETTER_AUTH_SECRET",
    "APPLE_TEAM_ID",
    "APPLE_KEY_ID",
    "APPLE_PRIVATE_KEY",
    "PROVIDER_TOKEN_ENCRYPTION_KEY",
  ];
  return required.filter((key) => !env[key]);
}

export function assertConfigured(env: Env): void {
  const missing = missingCoreConfiguration(env);
  if (missing.length > 0) {
    throw new Error(`Missing required configuration: ${missing.join(", ")}`);
  }
}

export function isStripeConfigured(env: Env): boolean {
  return Boolean(env.STRIPE_CONNECT_CLIENT_ID && env.STRIPE_SECRET_KEY);
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
