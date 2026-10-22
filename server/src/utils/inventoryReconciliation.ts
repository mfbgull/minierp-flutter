import Database from 'better-sqlite3';

export interface InventoryReconciliationDescription {
  description: string;
  inventoryLineDescription: string;
  adjustmentLineDescription: string;
  amount: number;
}

/**
 * Posts the RECON journal entry for an inventory reconciliation.
 * Callers own the transaction; this helper deliberately does not start one.
 */
export function postInventoryReconciliationEntry(
  db: Database.Database,
  options: InventoryReconciliationDescription
): void {
  const { description, inventoryLineDescription, adjustmentLineDescription, amount } = options;
  if (amount <= 0.005) return;
  if (!db.prepare(`SELECT name FROM sqlite_master WHERE type='table' AND name='journal_entries'`).get()) return;

  const today = new Date().toISOString().split('T')[0];
  const entry = db.prepare(`
    INSERT INTO journal_entries (reference_type, reference_id, entry_date, description, debit_account, credit_account, amount, voided)
    VALUES ('RECON', 0, ?, ?, '1200', '4999', ?, 0)
  `).run(today, description, amount);

  const entryId = entry.lastInsertRowid as number;
  const inventoryAccount = db.prepare(`SELECT id FROM chart_of_accounts WHERE code = '1200'`).get() as { id: number } | undefined;
  const adjustmentAccount = db.prepare(
    `SELECT id FROM chart_of_accounts WHERE code IN ('4999','4000') ORDER BY code DESC LIMIT 1`
  ).get() as { id: number } | undefined;
  if (!inventoryAccount || !adjustmentAccount) return;

  const lines = db.prepare(`
    INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description, line_date)
    VALUES (?, ?, ?, ?, ?, ?)
  `);
  lines.run(entryId, inventoryAccount.id, amount, 0, inventoryLineDescription, today);
  lines.run(entryId, adjustmentAccount.id, 0, amount, adjustmentLineDescription, today);
}
