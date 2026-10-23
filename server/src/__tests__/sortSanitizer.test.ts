import { describe, expect, it } from '@jest/globals';
import { sanitizeSortParams } from '../utils/sqlSanitizer';

/**
 * Regression for the ledger sort bug found by the Fallow coverage batch:
 * explicit ASC was silently replaced by the default when the default was
 * DESC, so supplier/customer ledgers could never sort oldest-first.
 */
describe('sanitizeSortParams', () => {
  const columns = ['transaction_date', 'amount'] as const;

  it('honors explicit ASC and DESC regardless of the default', () => {
    expect(
      sanitizeSortParams('amount', 'ASC', columns, 'transaction_date', 'DESC')
        .order,
    ).toBe('ASC');
    expect(
      sanitizeSortParams('amount', 'DESC', columns, 'transaction_date', 'DESC')
        .order,
    ).toBe('DESC');
    expect(
      sanitizeSortParams('amount', 'ASC', columns, 'transaction_date', 'ASC')
        .order,
    ).toBe('ASC');
  });

  it('falls back to the default order for unknown directions', () => {
    expect(
      sanitizeSortParams('amount', 'sideways', columns, 'transaction_date', 'DESC')
        .order,
    ).toBe('DESC');
    expect(
      sanitizeSortParams('amount', '', columns, 'transaction_date', 'ASC')
        .order,
    ).toBe('ASC');
  });

  it('falls back to the default column for unknown columns', () => {
    expect(
      sanitizeSortParams('amount; DROP TABLE x', 'ASC', columns, 'transaction_date')
        .column,
    ).toBe('transaction_date');
  });
});
