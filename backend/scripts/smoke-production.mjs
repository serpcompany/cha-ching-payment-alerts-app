#!/usr/bin/env node

const bearerToken = process.env.CHA_CHING_SMOKE_BEARER_TOKEN;
const origin = new URL("https://cha-ching-api.serpcompany.workers.dev");
const expectedEnvironment = "production";

if (!bearerToken) {
  throw new Error("Set CHA_CHING_SMOKE_BEARER_TOKEN to a dedicated signed-in smoke account session");
}

async function getJSON(pathname, validate) {
  const response = await fetch(new URL(pathname, origin), {
    headers: { authorization: `Bearer ${bearerToken}` },
    redirect: "error",
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) throw new Error(`${pathname} returned ${response.status}`);
  if (!(response.headers.get("content-type") ?? "").includes("application/json")) {
    throw new Error(`${pathname} returned non-JSON content`);
  }
  const payload = await response.json();
  if (!payload || typeof payload !== "object" || !validate(payload)) {
    throw new Error(`${pathname} returned an unexpected response shape`);
  }
  console.log(`PASS ${pathname} (${response.status})`);
}

const healthResponse = await fetch(new URL("/health", origin), {
  redirect: "error",
  signal: AbortSignal.timeout(10_000),
});
if (!healthResponse.ok) throw new Error(`/health returned ${healthResponse.status}`);
const health = await healthResponse.json();
if (!health || typeof health !== "object" || health.environment !== expectedEnvironment) {
  throw new Error(`/health did not report environment ${expectedEnvironment}`);
}
console.log(`PASS /health (${healthResponse.status})`);

await getJSON("/v1/me", (payload) => typeof payload.user === "object" && payload.user !== null);
await getJSON(
  "/v1/subscription",
  (payload) => payload.access === "full_access" || payload.access === "subscription_required",
);
await getJSON("/v1/connections", (payload) => Array.isArray(payload.connections));
await getJSON("/v1/sales", (payload) => Array.isArray(payload.sales));
await getJSON("/v1/preferences", (payload) => "reportingTimezone" in payload);
await getJSON(
  "/v1/dashboard?period=4w",
  (payload) => typeof payload.reportingTimezone === "string"
    && typeof payload.today === "object"
    && typeof payload.report === "object",
);
