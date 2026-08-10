import { createAuth, requireUser } from "./auth";
import {
  beginConnection,
  completeConnection,
  disconnect,
  listConnections,
} from "./connections";
import { getUserEntitlements } from "./entitlements";
import type { Env } from "./env";
import { assertConfigured } from "./env";
import { homePage, privacyPage, termsPage } from "./legal";

function jsonError(error: unknown): Response {
  if (error instanceof Response) return error;
  console.error("request.failed", {
    message: error instanceof Error ? error.message : "Unknown error",
  });
  return Response.json({ error: "Internal server error" }, { status: 500 });
}

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  if (request.method === "GET" && url.pathname === "/") return homePage();
  if (request.method === "GET" && url.pathname === "/privacy") return privacyPage();
  if (request.method === "GET" && url.pathname === "/terms") return termsPage();
  if (request.method === "GET" && url.pathname === "/health") {
    return Response.json({ status: "ok", environment: env.ENVIRONMENT });
  }
  assertConfigured(env);
  const auth = createAuth(env);

  if (url.pathname.startsWith("/api/auth/")) return auth.handler(request);
  if (request.method === "GET" && url.pathname === "/v1/me") {
    const user = await requireUser(auth, request);
    const entitlements = await getUserEntitlements(env.DB, user.id);
    return Response.json({ user, entitlements });
  }
  if (request.method === "GET" && url.pathname === "/v1/connections") {
    return listConnections(env, auth, request);
  }

  const authorizeMatch = url.pathname.match(/^\/v1\/connections\/([^/]+)\/authorize$/);
  if (request.method === "POST" && authorizeMatch) {
    return beginConnection(env, auth, request, authorizeMatch[1]);
  }
  const callbackMatch = url.pathname.match(/^\/v1\/oauth\/([^/]+)\/callback$/);
  if (request.method === "GET" && callbackMatch) {
    return completeConnection(env, request, callbackMatch[1]);
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
} satisfies ExportedHandler<Env>;
