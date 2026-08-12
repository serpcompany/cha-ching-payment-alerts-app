import { createAuth, requireUser } from "./auth";
import { handleCustomSourceRequest } from "./custom-webhooks";
import {
  beginConnection,
  clearProviderPayments,
  completeConnection,
  disconnect,
  listConnections,
  setConnectionActivity,
} from "./connections";
import { registerDevice, unregisterDevice } from "./devices";
import { getUserEntitlements } from "./entitlements";
import type { Env } from "./env";
import {
  assertConfigured,
  isPayPalConfigured,
  isPushConfigured,
  isSimulatorAuthRequestAllowed,
  isStripeConfigured,
  missingCoreConfiguration,
  providerCapabilities,
} from "./env";
import { homePage, privacyPage, termsPage } from "./legal";
import { processNotificationBatch } from "./notifications";
import type { NotificationMessage } from "./notifications";
import { monitorCustomSourceHealth } from "./custom-source-health";
import { listSales } from "./sales";
import { handleStripeWebhook } from "./stripe-webhooks";

function jsonError(error: unknown): Response {
  if (error instanceof Response) return error;
  console.error(JSON.stringify({
    message: "request.failed",
    error: error instanceof Error ? error.message : "Unknown error",
  }));
  return Response.json({ error: "Internal server error" }, { status: 500 });
}

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  if (request.method === "GET" && url.pathname === "/") return homePage();
  if (request.method === "GET" && url.pathname === "/privacy") return privacyPage();
  if (request.method === "GET" && url.pathname === "/terms") return termsPage();
  if (request.method === "GET" && url.pathname === "/health") {
    const readiness = {
      authentication: missingCoreConfiguration(env).length === 0,
      stripeConnections: isStripeConfigured(env),
      stripeNotifications: isStripeConfigured(env) && Boolean(env.STRIPE_WEBHOOK_SECRET) && isPushConfigured(env),
      customWebhookNotifications: isPushConfigured(env),
      paypalConnections: isPayPalConfigured(env),
    };
    return Response.json({
      status: Object.values(readiness).every(Boolean) ? "ok" : "degraded",
      environment: env.ENVIRONMENT,
      readiness,
    });
  }
  if (request.method === "POST" && url.pathname === "/v1/webhooks/stripe") {
    return handleStripeWebhook(env, request);
  }
  if (
    url.pathname === "/api/auth/sign-in/anonymous"
    && !isSimulatorAuthRequestAllowed(env, request.url)
  ) {
    return Response.json({ error: "Not found" }, { status: 404 });
  }
  if (missingCoreConfiguration(env).length > 0) {
    return Response.json({ error: "Authentication service is not configured" }, { status: 503 });
  }
  assertConfigured(env);
  const auth = createAuth(env);

  if (
    url.pathname === "/v1/custom-sources"
    || url.pathname.startsWith("/v1/custom-sources/")
    || url.pathname.startsWith("/v1/webhooks/custom/")
  ) {
    return handleCustomSourceRequest(env, auth, request);
  }

  if (url.pathname.startsWith("/api/auth/")) return auth.handler(request);
  if (request.method === "GET" && url.pathname === "/v1/me") {
    const user = await requireUser(auth, request);
    const entitlements = await getUserEntitlements(env.DB, user.id);
    return Response.json({ user, entitlements, providerConnections: providerCapabilities(env) });
  }
  if (request.method === "GET" && url.pathname === "/v1/connections") {
    return listConnections(env, auth, request);
  }
  if (request.method === "GET" && url.pathname === "/v1/sales") {
    return listSales(env, auth, request);
  }
  if (request.method === "POST" && url.pathname === "/v1/devices") {
    return registerDevice(env, auth, request);
  }

  const authorizeMatch = url.pathname.match(/^\/v1\/connections\/([^/]+)\/authorize$/);
  if (request.method === "POST" && authorizeMatch) {
    return beginConnection(env, auth, request, authorizeMatch[1]);
  }
  const callbackMatch = url.pathname.match(/^\/v1\/oauth\/([^/]+)\/callback$/);
  if (request.method === "GET" && callbackMatch) {
    return completeConnection(env, request, callbackMatch[1]);
  }
  const deviceMatch = url.pathname.match(/^\/v1\/devices\/([^/]+)$/);
  if (request.method === "DELETE" && deviceMatch) {
    return unregisterDevice(env, auth, request, decodeURIComponent(deviceMatch[1]));
  }
  const connectionActivityMatch = url.pathname.match(/^\/v1\/connections\/([^/]+)\/(pause|resume)$/);
  if (request.method === "POST" && connectionActivityMatch) {
    return setConnectionActivity(
      env,
      auth,
      request,
      connectionActivityMatch[1],
      connectionActivityMatch[2] === "resume",
    );
  }
  const connectionPaymentsMatch = url.pathname.match(/^\/v1\/connections\/([^/]+)\/payments$/);
  if (request.method === "DELETE" && connectionPaymentsMatch) {
    return clearProviderPayments(env, auth, request, connectionPaymentsMatch[1]);
  }
  const connectionMatch = url.pathname.match(/^\/v1\/connections\/([^/]+)$/);
  if (request.method === "DELETE" && connectionMatch) {
    return disconnect(env, auth, request, connectionMatch[1]);
  }

  return Response.json({ error: "Not found" }, { status: 404 });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return await route(request, env);
    } catch (error) {
      return jsonError(error);
    }
  },
  async queue(batch: MessageBatch<NotificationMessage>, env: Env): Promise<void> {
    await processNotificationBatch(env, batch);
  },
  async scheduled(_controller: ScheduledController, env: Env): Promise<void> {
    await monitorCustomSourceHealth(env);
  },
} satisfies ExportedHandler<Env, NotificationMessage>;
