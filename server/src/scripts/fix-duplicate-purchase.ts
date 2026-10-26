import Database from 'better-sqlite3';
import path from 'path';
import fs from 'fs';
import { defaultDbDir } from '../utils/serverRoot';

const PURCHASE_NO = 'PURCH-2026-0004';

class DuplicatePurchaseRepairError extends Error {}

interface RepairPurchase {
  readonly id: number;
  readonly warehouse_id: number;
  readonly quantity: number;
  readonly total_cost: number;
  readonly voided_at: string | null;
}

function resolveRepairDatabase(): string {
  const directory = process.env.DATABASE_PATH;
  if (!directory?.trim()) {
    throw new DuplicatePurchaseRepairError('Set DATABASE_PATH to an isolated current-schema database directory.');
  }
  const candidate = path.resolve(directory, 'erp.db');
  const canonical = path.resolve(defaultDbDir(), 'erp.db');
  if (candidate === canonical) {
    throw new DuplicatePurchaseRepairError('Refusing the canonical live database; use an isolated copy.');
  }
  const candidateInfo = fs.statSync(candidate);
  const canonicalInfo = fs.statSync(canonical, { throwIfNoEntry: false });
  if (canonicalInfo && (fs.realpathSync(candidate) === fs.realpathSync(canonical)
    || (candidateInfo.dev === canonicalInfo.dev && candidateInfo.ino === canonicalInfo.ino))) {
    throw new DuplicatePurchaseRepairError('Refusing an alias of the canonical live database; use an isolated copy.');
  }
  return candidate;
}

async function main(): Promise<void> {
  const dbPath = resolveRepairDatabase();
  const preview = new Database(dbPath, { readonly: true, fileMustExist: true });
  let purchase: RepairPurchase | undefined;
  try {
    purchase = preview.prepare<unknown[], RepairPurchase>(
      'SELECT id, warehouse_id, quantity, total_cost, voided_at FROM purchases WHERE purchase_no = ?'
    ).get(PURCHASE_NO);
  } finally {
    preview.close();
  }
  if (!purchase || purchase.voided_at) {
    console.log(`${PURCHASE_NO}: nothing to fix (missing or already voided).`);
    return;
  }
  console.log(`${PURCHASE_NO}: ${purchase.quantity} units in warehouse ${purchase.warehouse_id}, amount ${purchase.total_cost}.`);
  if (!process.argv.includes('--apply')) {
    console.log('Read-only preview. Re-run with --apply to use the protected purchase void operation.');
    return;
  }

  process.env.DATABASE_PATH = path.dirname(dbPath);
  const { default: db } = await import('../config/database');
  try {
    const backupPath = `${dbPath}.backup-${Date.now()}-${process.pid}`;
    await db.backup(backupPath);
    console.log(`Backup written to: ${backupPath}`);
    const { default: PurchaseModel } = await import('../models/Purchase');
    PurchaseModel.void(purchase.id, 1, `Duplicate purchase correction: ${PURCHASE_NO}`, db);
    console.log(`${PURCHASE_NO}: voided with stock, supplier ledger and GL reversal; original record retained.`);
  } finally {
    db.close();
  }
}

void main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : 'Duplicate purchase repair failed.');
  process.exitCode = 1;
});
