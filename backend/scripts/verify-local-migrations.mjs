#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const backendDirectory = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const stateDirectory = await mkdtemp(path.join(tmpdir(), "cha-ching-d1-migrations-"));

function runWrangler(args) {
  const result = spawnSync("pnpm", ["exec", "wrangler", ...args], {
    cwd: backendDirectory,
    stdio: "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`Wrangler exited with status ${result.status ?? "unknown"}`);
}

try {
  const target = ["cha-ching-prod", "--local", "--persist-to", stateDirectory];
  runWrangler(["d1", "migrations", "apply", ...target]);
  runWrangler(["d1", "migrations", "apply", ...target]);
} finally {
  await rm(stateDirectory, { recursive: true, force: true });
}
