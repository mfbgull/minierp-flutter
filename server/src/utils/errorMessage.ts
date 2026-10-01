/**
 * Narrowing helper for a caught value.
 *
 * `catch (error: unknown)` is the honest annotation — anything can be
 * thrown, not just an Error — but it makes every `.message` read a
 * compile error. This centralises the narrowing so the 160-odd catch
 * clauses can say `errorMessage(error)` instead of casting at each site.
 *
 * It also handles the shapes the old `any` annotation silently allowed:
 * a thrown string, or a plain object carrying `message`, both of which
 * read as `undefined` under `(error as Error).message`.
 */
export function errorMessage(error: unknown): string {
  if (typeof error === 'string') return error;
  if (error instanceof Error) return error.message;
  if (error !== null && typeof error === 'object' && 'message' in error) {
    const message = (error as { message?: unknown }).message;
    if (typeof message === 'string') return message;
  }
  return String(error);
}

/** Stack for a caught value, when it has one. */
export function errorStack(error: unknown): string | undefined {
  return error instanceof Error ? error.stack : undefined;
}

/**
 * The error's NAME, e.g. `TokenExpiredError`.
 *
 * Distinct from [errorMessage]: jsonwebtoken's expired-token error has the
 * name `TokenExpiredError` and the message `jwt expired`, so code that
 * branches on the name must not read the message.
 */
export function errorName(error: unknown): string | undefined {
  if (error instanceof Error) return error.name;
  if (error !== null && typeof error === 'object' && 'name' in error) {
    const name = (error as { name?: unknown }).name;
    if (typeof name === 'string') return name;
  }
  return undefined;
}

/**
 * A driver-level error CODE, e.g. better-sqlite3's `SQLITE_CONSTRAINT_UNIQUE`.
 *
 * Kept separate from [errorMessage] because callers branch on the code while
 * the message is a human sentence.
 */
export function errorCode(error: unknown): string | undefined {
  if (error !== null && typeof error === 'object' && 'code' in error) {
    const code = (error as { code?: unknown }).code;
    if (typeof code === 'string') return code;
  }
  return undefined;
}

/** Narrow a caught value to an Error, for the rare site that needs a type. */
export function asError(error: unknown): Error {
  return error instanceof Error ? error : new Error(errorMessage(error));
}