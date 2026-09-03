import { readFile } from "node:fs/promises";
import { join } from "node:path";

export async function applyMigration(db: D1Database, migration: string): Promise<void> {
  const sql = await readFile(join(process.cwd(), "migrations", migration), "utf8");
  const statements = sql
    .replace(/--.*$/gm, "")
    .split(";")
    .map((statement) => statement.trim())
    .filter((statement) => statement && !statement.startsWith("PRAGMA foreign_keys"));
  for (const statement of statements) await db.prepare(statement).run();
}
