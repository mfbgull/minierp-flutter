import { describe, expect, it } from '@jest/globals';
import { executeReport, type FilterDef } from '../services/reportQueryEngine';

/**
 * Fallow health remediation — `reportQueryEngine.buildFilterExpression`
 * logical-group branches (CRAP 30).
 */
function run(filters: FilterDef[]): ReturnType<typeof executeReport> {
  return executeReport({
    entity: 'invoices',
    columns: [{ field: 'invoice_no' }],
    filters,
  });
}

const statusIsPaid: FilterDef = { field: 'status', operator: 'equals', value: 'Paid' };
const totalAbove: FilterDef = { field: 'total_amount', operator: 'greater_than', value: 0 };

describe('report filter logical groups', () => {
  it('joins a multi-child AND group', () => {
    expect(() =>
      run([{ operator: 'equals' as FilterDef['operator'], logicalOperator: 'AND', children: [statusIsPaid, totalAbove] }])
    ).not.toThrow();
  });

  it('joins a multi-child OR group', () => {
    expect(() =>
      run([{ operator: 'equals' as FilterDef['operator'], logicalOperator: 'OR', children: [statusIsPaid, totalAbove] }])
    ).not.toThrow();
  });

  it('collapses a single surviving child', () => {
    expect(() =>
      run([
        {
          operator: 'equals' as FilterDef['operator'],
          logicalOperator: 'AND',
          children: [statusIsPaid, { operator: 'equals' }],
        },
      ])
    ).not.toThrow();
  });

  it('drops a group whose children all render empty', () => {
    expect(() =>
      run([
        {
          operator: 'equals' as FilterDef['operator'],
          logicalOperator: 'OR',
          children: [{ operator: 'equals' }, { operator: 'equals' }],
        },
        statusIsPaid,
      ])
    ).not.toThrow();
  });

  it('ignores an empty child list and a field-less filter', () => {
    expect(() =>
      run([
        { operator: 'equals' as FilterDef['operator'], logicalOperator: 'AND', children: [] },
        { operator: 'equals' },
        totalAbove,
      ])
    ).not.toThrow();
  });

  it('handles nested groups', () => {
    expect(() =>
      run([
        {
          operator: 'equals' as FilterDef['operator'],
          logicalOperator: 'OR',
          children: [
            {
              operator: 'equals' as FilterDef['operator'],
              logicalOperator: 'AND',
              children: [statusIsPaid, totalAbove],
            },
            totalAbove,
          ],
        },
      ])
    ).not.toThrow();
  });
});
