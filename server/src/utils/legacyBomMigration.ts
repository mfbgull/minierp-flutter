import type Database from 'better-sqlite3';

/** Legacy `bom` header row copied into the current `boms` table. */
interface LegacyBomRow {
  id: number;
  bom_no: string | null;
  finished_item_id: number | null;
  quantity: number | null;
  is_active: number | null;
  notes: string | null;
  created_by: number | null;
  created_at: string | null;
  updated_at: string | null;
}

function legacyBomValues(legacy: LegacyBomRow, bomNo: string, fallbackUser: number) {
  return [
    bomNo,
    bomNo,
    Number(legacy.finished_item_id) || 0,
    Number(legacy.quantity) || 1,
    legacy.notes ?? null,
    legacy.is_active ?? 1,
    Number(legacy.created_by) || fallbackUser,
    legacy.created_at ?? null,
    legacy.updated_at ?? null,
  ] as const;
}

export function migrateLegacyBomHeaders(targetDb: Database.Database, tableExists: (name: string) => boolean, bomIdMap: Map<number, number>): void {
  if (!tableExists('bom')) return;

  const legacyBoms = targetDb
    .prepare(`
      SELECT id, bom_no, finished_item_id, quantity, is_active, notes,
             created_by, created_at, updated_at
      FROM bom
    `)
    .all() as LegacyBomRow[];
  const fallbackUser =
    (
      targetDb.prepare(`SELECT MIN(id) AS id FROM users`).get() as {
        id: number | null;
      }
    ).id ?? 1;
  const byNumber = targetDb.prepare(`SELECT id FROM boms WHERE bom_no = ?`);
  const idTaken = targetDb.prepare(`SELECT 1 FROM boms WHERE id = ?`);
  const insertWithId = targetDb.prepare(`
    INSERT INTO boms (
      id, bom_no, bom_name, finished_item_id, quantity, description,
      is_active, created_by, created_at, updated_at
    ) VALUES (
      ?, ?, ?, ?, ?, ?, ?, ?,
      COALESCE(?, CURRENT_TIMESTAMP), COALESCE(?, CURRENT_TIMESTAMP)
    )
  `);
  const insertAuto = targetDb.prepare(`
    INSERT INTO boms (
      bom_no, bom_name, finished_item_id, quantity, description,
      is_active, created_by, created_at, updated_at
    ) VALUES (
      ?, ?, ?, ?, ?, ?, ?,
      COALESCE(?, CURRENT_TIMESTAMP), COALESCE(?, CURRENT_TIMESTAMP)
    )
  `);

  for (const legacy of legacyBoms) {
    const legacyId = Number(legacy.id);
    const bomNo =
      String(legacy.bom_no ?? '').trim() || `BOM-${legacyId || 'LEGACY'}`;
    const existing = byNumber.get(bomNo) as { id: number } | undefined;
    if (existing) {
      bomIdMap.set(legacyId, existing.id);
      continue;
    }

    const values = legacyBomValues(legacy, bomNo, fallbackUser);

    if (!idTaken.get(legacyId)) {
      insertWithId.run(legacyId, ...values);
      bomIdMap.set(legacyId, legacyId);
    } else {
      const result = insertAuto.run(...values);
      bomIdMap.set(legacyId, Number(result.lastInsertRowid));
    }
  }
}
