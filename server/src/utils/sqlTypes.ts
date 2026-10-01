/**
 * A value that can be bound to a better-sqlite3 statement.
 *
 * Query builders accumulate their bind values into a `SqlParam[]` and spread
 * them into `.all(...)` / `.run(...)`. Typing that accumulator is what lets
 * the compiler check the call, where `any[]` silenced it.
 */
export type SqlParam = string | number | bigint | Buffer | null;

/** A row from a query whose shape the caller has not narrowed yet. */
export type SqlRow = Record<string, unknown>;