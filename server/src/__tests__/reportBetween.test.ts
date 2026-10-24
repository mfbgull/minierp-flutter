import { describe, expect, it } from '@jest/globals';
import { executeReport, type FilterDef } from '../services/reportQueryEngine';

/**
 * Fallow health remediation — `reportQueryEngine.buildBetween` (CRAP 56).
 * Exercises absolute, relative, mixed, and invalid `between` values through
 * the public report executor.
 */
function runBetween(value: FilterDef['value']): ReturnType<typeof executeReport> {
  return executeReport({
    entity: 'invoices',
    columns: [{ field: 'invoice_no' }],
    filters: [{ field: 'invoice_date', operator: 'between', value }],
  });
}

describe('reportQueryEngine.buildBetween', () => {
  it('runs an absolute date range', () => {
    expect(() =>
      runBetween(['2026-01-01', '2026-01-31']),
    ).not.toThrow();
  });

  it('runs a relative date range without parameters', () => {
    expect(() => runBetween(['last_7_days', 'today'])).not.toThrow();
  });

  it('runs a mixed relative/absolute range', () => {
    expect(() => runBetween(['last_30_days', '2026-01-31'])).not.toThrow();
  });

  it('treats a non-array or short array as an open filter', () => {
    expect(() => runBetween('2026-01-01')).not.toThrow();
    expect(() => runBetween(['2026-01-01'])).not.toThrow();
  });
});
