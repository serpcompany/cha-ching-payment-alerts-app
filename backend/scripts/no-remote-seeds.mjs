#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const packageJson = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
const scripts = packageJson.scripts ?? {};

const offenders = Object.entries(scripts).filter(([name, command]) => {
  const lowerCommand = String(command).toLowerCase();
  const executesSeed = lowerCommand.includes("wrangler d1 execute")
    && (lowerCommand.includes("seed") || lowerCommand.includes("seeds/"));
  return (
    executesSeed &&
    (lowerCommand.includes("--remote") || !lowerCommand.includes("--local"))
  );
});

if (offenders.length > 0) {
  console.error("Seed scripts must be local-only and include --local.");
  for (const [name, command] of offenders) {
    console.error(`- ${name}: ${command}`);
  }
  process.exit(1);
}

console.log("Seed scripts are local-only.");
