#!/usr/bin/env node
/**
 * gl:recompute-item-amounts (ACC-18 interim) — recompute existing
 * invoice_items.amount from the stored qty/price/discount/tax columns and
 * report invoice headers whose total_amount diverges from the sum of the
 * recomputed lines.
 *
 * Line amount: round(qty × unit_price − discount) with tax applied at the
 * line boundary — identical to the server-side writer (utils/currency
 * computeLineAmount). Headers are REPORTED, never mutated (design D7:
 * divergent headers get a reconciliation listing, not silent correction).
 *
 * Idempotent: re-running finds nothing left to fix. Dry-run by default;
 * pass --apply to write corrected line amounts. Run `npm run db:backup`
 * first.
 *
 * Usage:
 *   node dist/scripts/recompute-item-amounts.js            (dry run)
 *   node dist/scripts/recompute-item-amounts.js --apply    (write)
 */
const path = require('path');
const fs = require('fs');

function roundCurrency(value) {
  return Number(Math.round(Number(value + 'e+2')) + 'e-2');
}

function parseCurrency(value) {
  if (value === null || value === undefined) return 0;
  const num = typeof value === 'number' ? value : parseFloat(String(value));
  return isNaN(num) ? 0 : roundCurrency(num);
}

function computeLineAmount(item) {
  const gross = roundCurrency(Number(item.quantity) * Number(item.unit_price));
  const discountValue = parseCurrency(item.discount_value || 0);
  let net = gross;
  if (discountValue > 0) {
    const discountAmount = item.discount_type === 'flat'
      ? roundCurrency(discountValue)
      : roundCurrency(gross * (discountValue / 100));
    net = roundCurrency(gross - Math.min(discountAmount, gross));
  }
  const taxRate = parseCurrency(item.tax_rate || 0);
  if (taxRate !== 0) {
    net = roundCurrency(net + roundCurrency(net * (taxRate / 100)));
  }
  return net;
}

function resolveDbPath() {
  const candidates = [
    process.env.DATABASE_PATH && path.join(process.env.DATABASE_PATH, 'erp.db'),
    process.env.DATABASE_PATH,
    path.join(__dirname, '../../../database/erp.db'),
    path.join(__dirname, '../../database/erp.db'),
  ].filter(Boolean);
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  console.error('[recompute-item-amounts] database not found; set DATABASE_PATH');
  process.exit(1);
}

function main() {
  const apply = process.argv.includes('--apply');
  const dbPath = resolveDbPath();
  const Database = require('better-sqlite3');
  const db = new Database(dbPath);

  try {
    const items = db.prepare(`
      SELECT id, invoice_id, quantity, unit_price, amount,
             tax_rate, discount_type, discount_value
      FROM invoice_items ORDER BY id
    `).all();

    const stale = items.filter(i => {
      const computed = computeLineAmount(i);
      return Math.abs(computed - Number(i.amount)) > 0.01;
    });

    console.log(`[recompute-item-amounts] ${items.length} line(s) scanned, ${stale.length} need recomputation`);
    for (const i of stale.slice(0, 50)) {
      const computed = computeLineAmount(i);
      console.log(`  item#${i.id} invoice=${i.invoice_id} stored=${Number(i.amount).toFixed(2)} -> computed=${computed.toFixed(2)} (qty=${i.quantity} price=${i.unit_price} disc=${i.discount_type}:${i.discount_value} tax=${i.tax_rate})`);
    }
    if (stale.length > 50) console.log(`  … and ${stale.length - 50} more`);

    if (!apply) {
      console.log('[recompute-item-amounts] dry run only — re-run with --apply to write line amounts');
    } else if (stale.length > 0) {
      const update = db.prepare('UPDATE invoice_items SET amount = ? WHERE id = ?');
      const tx = db.transaction(() => {
        for (const i of stale) update.run(computeLineAmount(i), i.id);
      });
      tx();
      console.log(`[recompute-item-amounts] wrote ${stale.length} corrected line amount(s)`);
    }

    // Header divergence report — informational only, never mutated (D7).
    const headers = db.prepare(`
      SELECT i.id, i.invoice_no, i.total_amount,
             COALESCE((SELECT SUM(amount) FROM invoice_items ii WHERE ii.invoice_id = i.id), 0) AS lines_sum
      FROM invoices i
    `).all();
    const divergent = headers.filter(h => Math.abs(Number(h.total_amount) - Number(h.lines_sum)) > 0.01);
    console.log(`[recompute-item-amounts] header divergence check: ${divergent.length} of ${headers.length} invoices differ from their line sums by more than 0.01`);
    for (const h of divergent.slice(0, 50)) {
      console.log(`  invoice#${h.id} ${h.invoice_no} header=${Number(h.total_amount).toFixed(2)} lines=${Number(h.lines_sum).toFixed(2)} delta=${(Number(h.total_amount) - Number(h.lines_sum)).toFixed(2)}`);
    }
    if (divergent.length > 50) console.log(`  … and ${divergent.length - 50} more`);

    console.log('[recompute-item-amounts] done');
  } finally {
    db.close();
  }
}

main();
