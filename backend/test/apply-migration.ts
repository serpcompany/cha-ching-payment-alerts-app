import { readFile } from "node:fs/promises";
import { join } from "node:path";

export async function applyMigration(db: D1Database, migration: string): Promise<void> {
  const sql = await readFile(join(process.cwd(), "migrations", migration), "utf8");
  const triggers = sql.match(/CREATE TRIGGER[\s\S]*?END;/g) ?? [];
  const ordinarySQL = triggers.reduce((value, trigger) => value.replace(trigger, ""), sql);
  const statements = ordinarySQL
    .replace(/--.*$/gm, "")
    .split(";")
    .map((statement) => statement.trim())
    .filter((statement) => statement && !statement.startsWith("PRAGMA foreign_keys"));
  for (const statement of statements) await db.prepare(statement).run();
  for (const trigger of triggers) await db.prepare(trigger).run();
}
