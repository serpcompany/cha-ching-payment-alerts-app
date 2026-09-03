#!/usr/bin/env node

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const backendDirectory = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const migrationsDirectory = path.join(backendDirectory, "migrations");
const migrationPattern = /^(\d{4,})_[a-z0-9_]+\.sql$/;

const entries = (await readdir(migrationsDirectory, { withFileTypes: true }))
  .filter((entry) => entry.isFile())
  .map((entry) => entry.name)
  .sort();

const unexpected = entries.filter((name) => !migrationPattern.test(name));
if (unexpected.length > 0) {
  throw new Error(`Unexpected files in migrations/: ${unexpected.join(", ")}`);
}

let previousPrefix = -1n;
let legacySequence = true;

for (const [index, name] of entries.entries()) {
  const match = name.match(migrationPattern);
  const prefix = match?.[1] ?? "";
  const numericPrefix = BigInt(prefix);
  if (numericPrefix <= previousPrefix) {
    throw new Error(`Migration prefix must be unique and increasing: ${name}`);
  }
  previousPrefix = numericPrefix;

  if (legacySequence && prefix.length === 4) {
    const expected = index + 1;
    if (Number(prefix) !== expected) {
      throw new Error(`Expected legacy migration ${String(expected).padStart(4, "0")}, found ${name}`);
    }
  } else {
    legacySequence = false;
  }
  if ((await readFile(path.join(migrationsDirectory, name), "utf8")).trim().length === 0) {
    throw new Error(`Migration ${name} is empty`);
  }
}

if (entries.length === 0) throw new Error("No migrations found");
console.log(`Validated ${entries.length} ordered migration files.`);
