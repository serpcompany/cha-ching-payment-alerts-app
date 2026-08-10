export type Provider = "stripe" | "paypal";

export interface Env {
  DB: D1Database;
  ENVIRONMENT: "development" | "staging" | "production";
  PUBLIC_BASE_URL: string;
  BETTER_AUTH_SECRET: string;
  APPLE_APP_BUNDLE_ID: string;
  APPLE_SERVICE_ID: string;
  APPLE_TEAM_ID: string;
  APPLE_KEY_ID: string;
  APPLE_PRIVATE_KEY: string;
  PROVIDER_TOKEN_ENCRYPTION_KEY: string;
  STRIPE_CONNECT_CLIENT_ID: string;
  STRIPE_SECRET_KEY: string;
  PAYPAL_ENVIRONMENT: "sandbox" | "live";
  PAYPAL_CLIENT_ID: string;
  PAYPAL_CLIENT_SECRET: string;
}

export function assertConfigured(env: Env): void {
  const required: Array<keyof Env> = [
    "BETTER_AUTH_SECRET",
    "APPLE_APP_BUNDLE_ID",
    "APPLE_SERVICE_ID",
    "APPLE_TEAM_ID",
    "APPLE_KEY_ID",
    "APPLE_PRIVATE_KEY",
    "PROVIDER_TOKEN_ENCRYPTION_KEY",
  ];
  const missing = required.filter((key) => !env[key]);
  if (missing.length > 0) {
    throw new Error(`Missing required configuration: ${missing.join(", ")}`);
  }
}
