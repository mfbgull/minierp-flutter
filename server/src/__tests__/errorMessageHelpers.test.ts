import { describe, expect, it } from '@jest/globals';
import { errorCode, errorMessage, errorName } from '../utils/errorMessage';

/**
 * Fallow health remediation — `errorCode` (CRAP 30); the sibling narrowing
 * helpers are asserted alongside so the shared contract stays pinned.
 */
describe('errorMessage helpers', () => {
  it('narrows thrown strings, Errors and message-shaped objects', () => {
    expect(errorMessage('plain text')).toBe('plain text');
    expect(errorMessage(new Error('boom'))).toBe('boom');
    expect(errorMessage({ message: 'object text' })).toBe('object text');
    expect(errorMessage({ message: 42 })).toBe('[object Object]');
    expect(errorMessage(null)).toBe('null');
    expect(errorMessage(undefined)).toBe('undefined');
    expect(errorMessage(7)).toBe('7');
  });

  it('reads the error name from Errors and name-shaped objects', () => {
    expect(errorName(new TypeError('bad'))).toBe('TypeError');
    expect(errorName({ name: 'TokenExpiredError' })).toBe('TokenExpiredError');
    expect(errorName({ name: 3 })).toBeUndefined();
    expect(errorName('no name')).toBeUndefined();
    expect(errorName(null)).toBeUndefined();
  });

  it('reads a driver-level code from code-shaped objects', () => {
    expect(errorCode({ code: 'SQLITE_CONSTRAINT_UNIQUE' })).toBe('SQLITE_CONSTRAINT_UNIQUE');
    expect(errorCode({ code: 19 })).toBeUndefined();
    expect(errorCode(new Error('no code'))).toBeUndefined();
    expect(errorCode('no code')).toBeUndefined();
    expect(errorCode(null)).toBeUndefined();
  });
});
