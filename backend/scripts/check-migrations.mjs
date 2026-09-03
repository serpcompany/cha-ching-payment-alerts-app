#!/usr/bin/env node

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const backendDirectory = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const migrationsDirectory = path.join(backendDirectory, "migrations");
const migrationPattern = /^(\d{4})_[a-z0-9_]+\.sql$/;

const entries = (await readdir(migrationsDirectory, { withFileTypes: true }))
  .filter((entry) => entry.isFile())
  .map((entry) => entry.name)
  .sort();

const unexpected = entries.filter((name) => !migrationPattern.test(name));
if (unexpected.length > 0) {
  throw new Error(`Unexpected files in migrations/: ${unexpected.join(", ")}`);
}

for (const [index, name] of entries.entries()) {
  const match = name.match(migrationPattern);
  const expected = index + 1;
  const actual = Number(match?.[1]);
  if (actual !== expected) {
    throw new Error(`Expected migration ${String(expected).padStart(4, "0")}, found ${name}`);
  }
  if ((await readFile(path.join(migrationsDirectory, name), "utf8")).trim().length === 0) {
    throw new Error(`Migration ${name} is empty`);
  }
}

if (entries.length === 0) throw new Error("No migrations found");
console.log(`Validated ${entries.length} ordered migration files.`);
