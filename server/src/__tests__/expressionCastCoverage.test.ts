import { describe, expect, it } from '@jest/globals';
import { ExpressionValidationError, validateExpression } from '../services/expressionValidator';

/**
 * Fallow health remediation — `expressionValidator.parseCastArguments`
 * (CRAP 240). CAST is the only grammar production that takes a type name.
 */
describe('CAST validation', () => {
  const fields = new Set(['total_amount']);

  it('accepts every whitelisted cast target in either case', () => {
    for (const type of ['INTEGER', 'INT', 'REAL', 'FLOAT', 'TEXT', 'NUMERIC', 'DECIMAL']) {
      expect(() => validateExpression(`CAST(total_amount AS ${type})`, fields)).not.toThrow();
    }
    expect(() => validateExpression('cast(total_amount as text)', fields)).not.toThrow();
  });

  it('requires the AS keyword', () => {
    expect(() => validateExpression('CAST(total_amount TEXT)', fields)).toThrow(
      ExpressionValidationError
    );
    expect(() => validateExpression('CAST(total_amount AS)', fields)).toThrow(
      /CAST target type must be one of/
    );
  });

  it('rejects a non-whitelisted target type', () => {
    expect(() => validateExpression('CAST(total_amount AS BLOB)', fields)).toThrow(
      /CAST target type must be one of/
    );
  });

  it('rejects a missing closing parenthesis', () => {
    expect(() => validateExpression('CAST(total_amount AS INTEGER', fields)).toThrow(
      /Missing closing parenthesis/
    );
  });
});
