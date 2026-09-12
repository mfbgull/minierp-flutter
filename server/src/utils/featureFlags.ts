import Database from 'better-sqlite3';

export function isFeatureEnabled(db: Database.Database, key: string): boolean {
  const row = db.prepare(`SELECT value FROM settings WHERE key = ?`).get(key) as { value: string } | undefined;
  return row?.value === '1';
}

export function setFeatureEnabled(db: Database.Database, key: string, enabled: boolean): void {
  db.prepare(`INSERT INTO settings (key, value) VALUES (?, ?)
    ON CONFLICT(key) DO UPDATE SET value = excluded.value`).run(key, enabled ? '1' : '0');
}
