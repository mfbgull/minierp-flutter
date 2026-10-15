/**
 * Evaluates accounting invariants A–J against the LIVE database using the
 * project's own collectors (server/src/__tests__/helpers/accountingInvariants.ts),
 * so this cannot drift from what the test-suite asserts.
 *
 * DATABASE_PATH must point at the live dir: when ts-node runs from src/,
 * config/database.ts resolves ../../../database -> the stale repo-root copy.
 */
import {
  glImbalances,
  customerArImbalances,
  supplierApImbalances,
  stockImbalances,
  arImbalances,
  apImbalances,
  inventoryImbalances,
  cashImbalances,
  orphanSourceBatches,
} from '../src/__tests__/helpers/accountingInvariants';

const results: Array<{ invariant: string; name: string; violations: unknown[] }> = [];

const gl = glImbalances();
results.push({
  invariant: 'A',
  name: 'GL balance: every reference group debit == credit',
  violations: gl.groups.map((g) => `${g.reference_type}#${g.reference_id} diff=${g.diff}`).concat(
    gl.totalDiff !== 0 ? [`LEDGER totalDiff=${gl.totalDiff}`] : []
  ),
});
results.push({ invariant: 'B/C', name: 'customer subledger + invoice allocations', violations: customerArImbalances() });
results.push({ invariant: 'D', name: 'supplier subledger', violations: supplierApImbalances() });
results.push({ invariant: 'E', name: 'stock_balances == sum of batch quantity_remaining', violations: stockImbalances() });
results.push({ invariant: 'F', name: 'GL AR (1100+1110) == customer balances', violations: arImbalances() });
results.push({ invariant: 'G', name: 'GL AP (2000) == supplier balances', violations: apImbalances() });
results.push({ invariant: 'H', name: 'GL inventory (1200) == batch + legacy item values', violations: inventoryImbalances() });
results.push({ invariant: 'I', name: 'GL cash accounts == operational cash flows', violations: cashImbalances() });
results.push({ invariant: 'J', name: 'source-typed batches resolve to their source', violations: orphanSourceBatches() });

console.log('\n=== ACCOUNTING INVARIANTS A–J (live database) ===');
for (const r of results) {
  const ok = r.violations.length === 0;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${r.invariant.padEnd(5)} ${r.name}`);
  if (!ok) console.log('        ' + JSON.stringify(r.violations, null, 2).split('\n').join('\n        '));
}
const failed = results.filter((r) => r.violations.length > 0);
console.log(failed.length === 0
  ? '\n*** ALL INVARIANTS A–J HOLD ***'
  : `\n*** ${failed.length} INVARIANT(S) VIOLATED ***`);
process.exit(failed.length ? 1 : 0);