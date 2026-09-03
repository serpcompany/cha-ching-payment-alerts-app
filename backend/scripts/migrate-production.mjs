#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

if (process.env.CONFIRM_PRODUCTION_MIGRATIONS !== "cha-ching-prod") {
  throw new Error(
    "Refusing to mutate production. Complete the promotion checklist, then set CONFIRM_PRODUCTION_MIGRATIONS=cha-ching-prod.",
  );
}
if (process.argv.length > 2) {
  throw new Error("db:migrate:production accepts no arguments");
}

const backendDirectory = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const result = spawnSync(
  "pnpm",
  ["exec", "wrangler", "d1", "migrations", "apply", "cha-ching-prod", "--remote"],
  { cwd: backendDirectory, stdio: "inherit" },
);
if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
