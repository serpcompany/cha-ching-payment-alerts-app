#!/usr/bin/env node

import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const packageJson = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
const scripts = packageJson.scripts ?? {};

const candidates = Object.entries(scripts)
  .filter(([name]) => name.toLowerCase().includes("seed"))
  .map(([name, command]) => [`package.json#${name}`, String(command)]);

const scriptsDirectory = join(root, "scripts");
for (const entry of readdirSync(scriptsDirectory, { withFileTypes: true })) {
  if (
    !entry.isFile()
    || entry.name === "no-remote-seeds.mjs"
    || !entry.name.toLowerCase().includes("seed")
  ) continue;
  candidates.push([
    `scripts/${entry.name}`,
    readFileSync(join(scriptsDirectory, entry.name), "utf8"),
  ]);
}

const offenders = candidates.filter(([, source]) => {
  const lowerSource = source.toLowerCase();
  const executesD1 = lowerSource.includes("wrangler")
    && lowerSource.includes("d1")
    && lowerSource.includes("execute");
  return executesD1
    && (lowerSource.includes("--remote") || !lowerSource.includes("--local"));
});

if (offenders.length > 0) {
  console.error("Seed scripts must be local-only and include --local.");
  for (const [name] of offenders) {
    console.error(`- ${name}`);
  }
  process.exit(1);
}

console.log("Seed scripts are local-only.");
