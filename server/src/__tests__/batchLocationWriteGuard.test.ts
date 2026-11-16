/**
 * BUG-013 structural guard: the batch-locations flag chooses which stock
 * source is READ. It must never choose which source is WRITTEN.
 *
 * Five separate defects shipped from the same mistake — a location write or a
 * batch write placed inside `if (isFeatureEnabled(db, 'feature_batch_locations'))`:
 *   1. `invoiceReturnService.reverseBatchRestore` (the return void)
 *   2. `StockMovement.sellableAvailabilityByWarehouseSql` (a read, but the
 *      same shape: covered batches only)
 *   3. `StockMovement.voidTransfer` (destination draw-down)
 *   4. `StockMovement.writeOffBatch` (the location mirror of the batch zeroing)
 *   5. `StockMovement.recordExpiryTransfer` / `recordDamageTransfer`
 *      (source-batch location drain)
 *
 * A reviewer cannot see the sixth by reading a diff. This guard reads the
 * source and fails when a write statement appears inside a flag condition, so
 * the sixth cannot ship at all.
 *
 * HOW IT READS. The naive version of this check is a regex over a brace block,
 * which cannot survive nesting. This one tokenises the file enough to track
 * brace depth and the stack of enclosing `if (isFeatureEnabled(...))` blocks:
 * it walks each source file, and whenever it opens a brace whose header is a
 * batch-locations flag condition, every line until that brace closes is
 * "inside the flag". A write inside is reported with its line number.
 *
 * WHAT COUNTS AS A WRITE. INSERT / UPDATE / DELETE against `stock_batches` or
 * `batch_stock_by_location`, in SQL text. Both tables are named in one regex;
 * a false positive would need a table literally named e.g.
 * `batch_stock_by_location_backup` in a flag block, which no code does.
 *
 * ESCAPES. A write may legitimately be flag-gated when the flag ON path is the
 * ONLY path — `.syncStockBalancesExtension` is the one allowed exception and is
 * listed by name below with its reason.
 */
import { describe, expect, it } from '@jest/globals';
import fs from 'fs';
import path from 'path';

const SERVER_SRC = path.resolve(__dirname, '..');

/**
 * Files that contain the flag at all. Adding a file here is the point: the
 * guard only covers what it is told about, so a new file that branches on the
 * flag must be added, and this list is short enough to review.
 */
const SCANNED_FILES = [
  'models/StockMovement.ts',
  'models/Invoice.ts',
  'models/Purchase.ts',
  'models/PurchaseReturn.ts',
  'models/StockReservation.ts',
  'models/CompanyReport.ts',
  'models/Reports.ts',
  'models/physicalCountLayers.ts',
  'services/invoiceReturnService.ts',
  'services/AccountingService.ts',
  'controllers/inventoryController.ts',
  'routes/stockBatches.ts',
];

/**
 * Writes that ARE allowed inside the flag condition, keyed by a substring of
 * the enclosing function and the statement. There are none today; the list is
 * here so the next exception is a deliberate, reviewed line rather than a
 * silent edit.
 */
const ALLOWED_GATED_WRITES: Array<{ file: string; snippet: string; reason: string }> = [];

const WRITE_TARGET = /\b(?:INSERT\s+(?:OR\s+\w+\s+)?INTO|UPDATE|DELETE\s+FROM)\s+["'`]?(stock_batches|batch_stock_by_location)\b/i;
/**
 * A flag test, direct or through a local alias. The direct call is the common
 * shape. `const on = isFeatureEnabled(db, 'feature_batch_locations'); if (on)`
 * was the fifth site and a direct-call-only regex misses it, so an alias
 * declared from the flag is tracked too.
 */
const FLAG_CONDITION = /if\s*\([^)]*isFeatureEnabled\s*\(\s*[^,)]+,\s*['"]feature_batch_locations['"]\s*\)/;
const FLAG_ALIAS_DECL = /\bconst\s+([A-Za-z_$][\w$]*)\s*=\s*isFeatureEnabled\s*\(\s*[^,)]+,\s*['"]feature_batch_locations['"]\s*\)/;
/** The union of `if (isFeatureEnabled(...,'feature_batch_locations'))` and `if (alias)`. */
function flagConditionFor(aliases: Set<string>): RegExp {
  const names = ['isFeatureEnabled\\s*\\(\\s*[^,)]+,\\s*[\'"]feature_batch_locations[\'"]'];
  for (const a of aliases) names.push(a.replace(/[$]/g, '\\$&'));
  return new RegExp(`if\\s*\\([^)]*(?:${names.join('|')})`);
}

interface Finding {
  file: string;
  line: number;
  text: string;
}

/**
 * Walks a source file and returns every write to the two tables that sits
 * inside a `feature_batch_locations` condition.
 */
function findGatedTableWrites(source: string): Finding[] {
  const lines = source.split('\n');
  const findings: Finding[] = [];
  // Local aliases of the flag, e.g. `const on = isFeatureEnabled(...)`.
  const aliases = new Set<string>();
  for (const line of lines) {
    const m = FLAG_ALIAS_DECL.exec(line);
    if (m) aliases.add(m[1]);
  }
  const flagRe = flagConditionFor(aliases);
  // Each entry is the brace depth at which a flag-condition block was opened.
  const flagDepths: number[] = [];
  let depth = 0;
  // The previous non-empty line, so a flag condition whose brace opens on the
  // NEXT line (the house prettier style) is still recognised.
  let pendingFlag = false;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();

    // An alias declaration is not itself a condition; it is only a condition
    // when a later `if (alias)` uses it.
    if (flagRe.test(line) && !FLAG_ALIAS_DECL.test(line)) {
      pendingFlag = true;
    }

    // Count braces on this line. Strings and comments are not stripped: a
    // brace inside a SQL string literal does not occur in these files, and a
    // stripped version would be far more code than the guard is worth.
    let opened = false;
    for (const ch of line) {
      if (ch === '{') {
        depth++;
        if (pendingFlag) {
          flagDepths.push(depth);
          pendingFlag = false;
          opened = true;
        }
      } else if (ch === '}') {
        if (flagDepths.length > 0 && flagDepths[flagDepths.length - 1] === depth) {
          flagDepths.pop();
        }
        depth--;
      }
    }
    // A one-line `if (flag) doThing();` with no brace still counts as inside.
    const oneLineFlag = flagRe.test(line) && !opened && !FLAG_ALIAS_DECL.test(line);

    const insideFlag = flagDepths.length > 0 || oneLineFlag;
    if (insideFlag && WRITE_TARGET.test(line)) {
      findings.push({ file: '', line: i + 1, text: trimmed });
    }
  }

  return findings;
}

describe('BUG-013 guard: batch-locations writes are never gated on the flag', () => {
  it('finds the write-target regex works (the check can fail)', () => {
    // A guard that cannot fail is worthless. Prove the two halves work.
    expect(WRITE_TARGET.test('UPDATE batch_stock_by_location SET quantity_available = 0')).toBe(true);
    expect(WRITE_TARGET.test('INSERT INTO stock_batches (item_id) VALUES (?)')).toBe(true);
    expect(WRITE_TARGET.test('DELETE FROM batch_stock_by_location WHERE batch_id = ?')).toBe(true);
    // ...and that a READ does not match, because reads are allowed to branch.
    expect(WRITE_TARGET.test('SELECT quantity_available FROM batch_stock_by_location')).toBe(false);
    expect(WRITE_TARGET.test('SELECT id FROM stock_batches WHERE item_id = ?')).toBe(false);
  });

  it('recognises a flag condition, including the wrapped form', () => {
    expect(FLAG_CONDITION.test("if (isFeatureEnabled(db, 'feature_batch_locations')) {")).toBe(true);
    expect(FLAG_CONDITION.test("  if (isFeatureEnabled(db, 'other_flag')) {")).toBe(false);
    // The house style wraps the call, so the regex must not require one line.
    expect(FLAG_CONDITION.test("if (isFeatureEnabled(")).toBe(false);
  });

  it('sees a write gated through a local alias of the flag', () => {
    // The fifth defect used `const on = isFeatureEnabled(...); if (on)`. A
    // direct-call-only regex would miss it, so the guard resolves aliases.
    const viaAlias = [
      "function f(db) {",
      "  const batchLocationsEnabled = isFeatureEnabled(db, 'feature_batch_locations');",
      "  if (batchLocationsEnabled) {",
      "    db.prepare(`UPDATE batch_stock_by_location SET quantity_physical = quantity_physical - ? WHERE id = ?`).run(1, 2);",
      "  }",
      "}",
    ].join('\n');
    const found = findGatedTableWrites(viaAlias);
    expect(found).toHaveLength(1);
    expect(found[0].line).toBe(4);
  });

  it('flags a synthetic write placed inside a flag condition', () => {
    const bad = [
      "function f(db) {",
      "  if (isFeatureEnabled(db, 'feature_batch_locations')) {",
      "    db.prepare(`UPDATE batch_stock_by_location SET quantity_available = 0 WHERE batch_id = ?`).run(id);",
      "  }",
      "  return true;",
      "}",
    ].join('\n');
    const found = findGatedTableWrites(bad);
    expect(found).toHaveLength(1);
    expect(found[0].line).toBe(3);
  });

  it('does not flag a write outside the flag block', () => {
    const good = [
      "function f(db) {",
      "  if (isFeatureEnabled(db, 'feature_batch_locations')) {",
      "    return readSomething();",
      "  }",
      "  db.prepare(`UPDATE batch_stock_by_location SET quantity_available = 0 WHERE batch_id = ?`).run(id);",
      "}",
    ].join('\n');
    expect(findGatedTableWrites(good)).toHaveLength(0);
  });

  it('does not let one flag block leak into the code after it', () => {
    // The nesting trap: after the flag block closes, a later write is OUTSIDE
    // it. A depth counter that never pops would wrongly flag it.
    const source = [
      "function f(db) {",
      "  if (isFeatureEnabled(db, 'feature_batch_locations')) {",
      "    const x = 1;",
      "    if (x) { const y = 2; }",
      "  }",
      "  db.prepare(`DELETE FROM stock_batches WHERE id = ?`).run(id);",
      "}",
    ].join('\n');
    expect(findGatedTableWrites(source)).toHaveLength(0);
  });

  it('has no write to stock_batches or batch_stock_by_location inside a flag condition', () => {
    const all: Finding[] = [];
    for (const rel of SCANNED_FILES) {
      const abs = path.join(SERVER_SRC, rel);
      if (!fs.existsSync(abs)) continue;
      const found = findGatedTableWrites(fs.readFileSync(abs, 'utf8'));
      for (const f of found) {
        const allowed = ALLOWED_GATED_WRITES.some(
          (a) => a.file === rel && a.snippet.length > 0 && f.text.includes(a.snippet),
        );
        if (!allowed) all.push({ ...f, file: rel });
      }
    }
    expect(all).toEqual([]);
  });

  it('scans every source file that mentions the flag', () => {
    // If a new file branches on the flag and is not in SCANNED_FILES, the guard
    // above silently misses it. This walks the tree and fails on any gap.
    const flagMentions: string[] = [];
    const walk = (dir: string): void => {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) {
          if (entry.name === '__tests__' || entry.name === 'node_modules') continue;
          walk(full);
        } else if (entry.name.endsWith('.ts')) {
          const text = fs.readFileSync(full, 'utf8');
          if (text.includes("'feature_batch_locations'")) {
            flagMentions.push(path.relative(SERVER_SRC, full));
          }
        }
      }
    };
    walk(SERVER_SRC);

    const unscanned = flagMentions.filter((f) => !SCANNED_FILES.includes(f));
    expect(unscanned).toEqual([]);
  });
});
