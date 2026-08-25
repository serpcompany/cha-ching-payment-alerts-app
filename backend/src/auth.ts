import { betterAuth } from "better-auth";
import { anonymous } from "better-auth/plugins/anonymous";
import { bearer } from "better-auth/plugins/bearer";
import { importPKCS8, SignJWT } from "jose";

import type { Env } from "./env";
import { isAppleConfigured, isSimulatorAuthEnabled } from "./env";

const MOBILE_SESSION_EXPIRES_IN_SECONDS = 60 * 60 * 24 * 365;
const MOBILE_SESSION_UPDATE_AGE_SECONDS = 60 * 60 * 24;

export async function appleClientSecret(
  env: Env,
  clientId: string = env.APPLE_SERVICE_ID,
): Promise<string> {
  const key = await importPKCS8(env.APPLE_PRIVATE_KEY.replace(/\\n/g, "\n"), "ES256");
  const now = Math.floor(Date.now() / 1_000);
  return new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: env.APPLE_KEY_ID })
    .setIssuer(env.APPLE_TEAM_ID)
    .setSubject(clientId)
    .setAudience("https://appleid.apple.com")
    .setIssuedAt(now)
    .setExpirationTime(now + 180 * 24 * 60 * 60)
    .sign(key);
}

export function createAuth(env: Env) {
  const socialProviders = isAppleConfigured(env)
    ? {
        apple: async () => ({
          clientId: env.APPLE_SERVICE_ID,
          clientSecret: await appleClientSecret(env),
          appBundleIdentifier: env.APPLE_APP_BUNDLE_ID,
          // Apple only includes email on first consent. Recover it from the
          // already-linked Better Auth account on later native sign-ins.
          mapProfileToUser: async (profile: { sub: string; email?: string | null }) => {
            if (profile.email) return {};
            const existing = await env.DB.prepare(
              `SELECT user.email, user.name
               FROM account
               JOIN user ON user.id = account.user_id
               WHERE account.provider_id = 'apple' AND account.account_id = ?1`,
            )
              .bind(profile.sub)
              .first<{ email: string; name: string }>();
            return existing ? { email: existing.email, name: existing.name } : {};
          },
        }),
      }
    : {};

  const plugins = isSimulatorAuthEnabled(env)
    ? [bearer(), anonymous({
        emailDomainName: "simulator.chaching.invalid",
        generateName: () => "Cha-Ching Simulator",
        schema: {
          user: {
            fields: {
              isAnonymous: "is_anonymous",
            },
          },
        },
      })]
    : [bearer()];

  return betterAuth({
    appName: "Cha-Ching",
    baseURL: env.PUBLIC_BASE_URL,
    basePath: "/api/auth",
    secret: env.BETTER_AUTH_SECRET,
    database: env.DB,
    trustedOrigins: ["https://appleid.apple.com", "chaching://", "chaching://*"],
    socialProviders,
    user: {
      fields: {
        emailVerified: "email_verified",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    session: {
      // Keep installed native clients signed in while preserving explicit
      // revocation and a finite inactivity boundary.
      expiresIn: MOBILE_SESSION_EXPIRES_IN_SECONDS,
      updateAge: MOBILE_SESSION_UPDATE_AGE_SECONDS,
      fields: {
        expiresAt: "expires_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
        ipAddress: "ip_address",
        userAgent: "user_agent",
        userId: "user_id",
      },
    },
    account: {
      fields: {
        accountId: "account_id",
        providerId: "provider_id",
        userId: "user_id",
        accessToken: "access_token",
        refreshToken: "refresh_token",
        idToken: "id_token",
        accessTokenExpiresAt: "access_token_expires_at",
        refreshTokenExpiresAt: "refresh_token_expires_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    verification: {
      fields: {
        expiresAt: "expires_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    plugins,
    advanced: {
      cookiePrefix: "cha-ching",
      useSecureCookies: env.ENVIRONMENT !== "development",
    },
    rateLimit: {
      enabled: true,
      storage: "database",
      modelName: "rate_limit",
      fields: { lastRequest: "last_request" },
      window: 60,
      max: 100,
    },
  });
}

export type Auth = ReturnType<typeof createAuth>;

export async function requireUser(auth: Auth, request: Request) {
  const session = await auth.api.getSession({ headers: request.headers });
  if (!session) {
    throw new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }
  return session.user;
}
