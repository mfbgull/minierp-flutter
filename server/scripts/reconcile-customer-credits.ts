import crypto from 'crypto';
import fs from 'fs';
import os from 'os';
import path from 'path';
import Database from 'better-sqlite3';
import { reconcileCustomerCredits } from '../src/services/creditReconciliation';
import { roundCurrency } from '../src/utils/currency';

function fingerprint(filename: string): string | null {
  return fs.existsSync(filename)
    ? crypto.createHash('sha256').update(fs.readFileSync(filename)).digest('hex')
    : null;
}

async function main(): Promise<void> {
  const sourcePath = process.argv[2];
  if (!sourcePath) throw new Error('Usage: ts-node scripts/reconcile-customer-credits.ts <source-db>');
  const files = [sourcePath, `${sourcePath}-wal`, `${sourcePath}-shm`];
  const before = files.map(fingerprint);
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'erp-credit-reconciliation-'));
  const snapshotPath = path.join(temporary, 'snapshot.db');
  try {
    const source = new Database(sourcePath, { readonly: true, fileMustExist: true });
    try {
      await source.backup(snapshotPath);
    } finally {
      source.close();
    }
    const db = new Database(snapshotPath, { readonly: true, fileMustExist: true });
    try {
      db.pragma('query_only = ON');
      const rows = reconcileCustomerCredits(db);
      const gl = db.prepare<[], { balance: number }>(`
        SELECT COALESCE(SUM(lines.debit)-SUM(lines.credit),0) balance
        FROM journal_lines lines JOIN chart_of_accounts accounts ON accounts.id=lines.account_id
        WHERE accounts.code IN ('1100','1110') AND lines.voided=0
      `).get();
      const customers = db.prepare<[], { receivable: number; storeCredit: number }>(`
        SELECT COALESCE(SUM(current_balance),0) receivable,
               COALESCE(SUM(credit_balance),0) storeCredit FROM customers
      `).get();
      if (!gl || !customers) throw new Error('Unable to read accounting baseline');
      const glBalance = roundCurrency(Math.abs(gl.balance));
      const customerBalance = roundCurrency(Math.abs(
        roundCurrency(customers.receivable) - roundCurrency(customers.storeCredit),
      ));
      const after = files.map(fingerprint);
      if (after.some((hash, index) => hash !== before[index])) {
        throw new Error('Source database or WAL/SHM changed; reconciliation evidence must be regenerated');
      }
      console.log(JSON.stringify({
        generatedAt: new Date().toISOString(),
        sourceHash: before[0],
        snapshotHash: fingerprint(snapshotPath),
        sourceFingerprintsUnchanged: true,
        rows,
        arBaseline: {
          glBalance,
          customerBalance,
          difference: roundCurrency(glBalance - customerBalance),
        },
      }, null, 2));
    } finally {
      db.close();
    }
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
