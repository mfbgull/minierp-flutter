import crypto from 'crypto';
import type Database from 'better-sqlite3';

/**
 * P11 — request idempotency (audit-remediation task 16).
 *
 * A POST can time out client-side AFTER the server committed. Retrying it
 * must not double-create. The client sends an `Idempotency-Key` header;
 * the first request stores its payload hash + created resource id in
 * `idempotency_keys`. Same key + same payload replays the original result;
 * same key + different payload is rejected. The server is authoritative —
 * UI submit guards alone cannot survive a retry.
 */

export const IDEMPOTENCY_KEY_HEADER = 'idempotency-key';
export const INVOICE_CREATE_SCOPE = 'invoice_create';
export const MOBILE_INVOICE_CREATE_SCOPE = 'mobile_invoice_create';
export const POS_SALE_SCOPE = 'pos_sale';

/**
 * audit-3 task 08: one scope per money-moving write handler.
 *
 * A scope is per operation, never per category — sharing one across two
 * operations risks a false-positive replay, and a key is only unique within
 * its scope, so a shared scope would also collide across them.
 *
 * Deliberate exception: PURCHASE_RECORD covers both the multi-item and the
 * single-item branch of `recordPurchase`. They are one endpoint and one
 * business operation, and the request hash already separates the two payload
 * shapes, so a single scope is correct rather than merely convenient.
 */
export const IDEMPOTENCY_SCOPES = {
  PAYMENT_CUSTOMER: 'payments.customer',
  PAYMENT_SUPPLIER: 'payments.supplier',
  PAYMENT_ALLOCATE: 'payments.allocate',
  EXPENSE_CREATE: 'expenses.create',
  PURCHASE_RECORD: 'purchases.record',
  PURCHASE_ORDER_RECEIPT: 'purchase-orders.receipt',
  INVOICE_RETURN: 'invoices.return',
  INVOICE_RETURN_SETTLE: 'invoice-returns.settle',
  OWNER_CAPITAL: 'owner-equity.capital',
  OWNER_WITHDRAWAL: 'owner-equity.withdrawal',
  EMPLOYEE_SALARY_PAY: 'employees.salary.pay',
  SUPPLIER_REFUND_CREATE: 'supplier-refunds.create',
} as const;

/** Normalize the raw header value; returns null when absent. Keys are
 * opaque client-chosen strings (UUID recommended), 8..200 chars. Throws on
 * a malformed key so client bugs surface early rather than silently
 * disabling protection. */
export function normalizeIdempotencyKey(raw: unknown): string | null {
  const value = Array.isArray(raw) ? raw[0] : raw;
  if (value === undefined || value === null || value === '') return null;
  const trimmed = String(value).trim();
  if (trimmed.length < 8 || trimmed.length > 200) {
    throw new Error('Idempotency-Key must be 8..200 characters');
  }
  return trimmed;
}

function canonicalize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const k of Object.keys(value as Record<string, unknown>).sort()) {
      const v = (value as Record<string, unknown>)[k];
      if (v !== undefined) out[k] = canonicalize(v);
    }
    return out;
  }
  return value;
}

/** Stable hash of the request payload — key order and volatile-but-absent
 * fields cannot change it, so "materially different" means real content
 * differences only. */
export function hashRequestPayload(body: unknown): string {
  return crypto.createHash('sha256').update(JSON.stringify(canonicalize(body))).digest('hex');
}

export interface IdempotencyRecord {
  request_hash: string;
  resource_id: number | null;
}

export function findIdempotencyRecord(
  db: Database.Database, scope: string, key: string,
): IdempotencyRecord | undefined {
  return db.prepare(
    'SELECT request_hash, resource_id FROM idempotency_keys WHERE scope = ? AND key = ?'
  ).get(scope, key) as IdempotencyRecord | undefined;
}

/**
 * Claim the key and link the created resource INSIDE the caller's create
 * transaction: the (key → resource) row persists if and only if the
 * document creation commits, so a rolled-back or crashed attempt leaves no
 * trace and the retry executes normally.
 */
export class IdempotencyConflictError extends Error {
  constructor() {
    super('Idempotency-Key was already used with a different request payload');
    this.name = 'IdempotencyConflictError';
  }
}

/**
 * Parse the header and, when a key is present, decide whether this request
 * is a retry of an already-committed write.
 *
 * Returns `replayId` = the resource the caller should re-read and return, or
 * null when the caller should proceed and claim the key itself. Throws
 * IdempotencyConflictError when the same key was used with a materially
 * different payload.
 *
 * Call this INSIDE the write transaction, next to where the key will be
 * claimed, so a key is only honoured if its transaction actually committed.
 */
export function beginIdempotentWrite(
  db: Database.Database, scope: string, key: string | null, requestHash: string,
): { replayId: number | null } {
  if (!key) return { replayId: null };
  const existing = findIdempotencyRecord(db, scope, key);
  if (!existing) return { replayId: null };
  if (existing.request_hash !== requestHash) throw new IdempotencyConflictError();
  return { replayId: existing.resource_id };
}

/**
 * Claim the key and link the created resource INSIDE the caller's write
 * transaction: the (key → resource) row persists if and only if the write
 * commits, so a rolled-back or crashed attempt leaves no trace and the retry
 * executes normally.
 */
export function claimIdempotencyKey(
  db: Database.Database, scope: string, key: string, requestHash: string, resourceId: number,
): void {
  db.prepare(`
    INSERT INTO idempotency_keys (key, scope, request_hash, resource_id, completed_at)
    VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
    ON CONFLICT(scope, key) DO UPDATE SET
      resource_id = excluded.resource_id,
      completed_at = excluded.completed_at
  `).run(key, scope, requestHash, resourceId);
}

/**
 * Prune completed keys past the retention window (decision 8.4). Only
 * completed rows are removed, so a key whose transaction never committed is
 * never pruned and a legitimate in-flight retry still matches.
 *
 * Returns the number of rows deleted.
 */
export function pruneIdempotencyKeys(
  db: Database.Database, retentionDays = 30, now = new Date(),
): number {
  const cutoff = new Date(now.getTime() - retentionDays * 86_400_000)
    .toISOString()
    .slice(0, 10);
  const result = db.prepare(`
    DELETE FROM idempotency_keys
    WHERE completed_at IS NOT NULL AND completed_at < ?
  `).run(cutoff);
  return result.changes;
}

/**
 * audit-3 task 08 (decision 8.2): the controller-facing entry point.
 *
 * One call replaces the header parse, the replay lookup and the
 * changed-payload rejection, so each keyed handler needs three lines rather
 * than the same five imports and a try/catch:
 *
 *   const start = startIdempotentRequest(db, req.headers, SCOPE, hash);
 *   if (start.kind === 'error') return res.status(start.status).json(...);
 *   if (start.kind === 'replay') return res.json(...);
 *   // ... perform the write, then:
 *   if (start.key) claimIdempotencyKey(db, SCOPE, start.key, hash, createdId);
 *
 * The caller MUST claim inside the same transaction as the write, and MUST
 * call this before the write, so the two agree on whether the operation
 * already happened.
 */
export type IdempotencyStart =
  | { kind: 'proceed'; key: string | null }
  | { kind: 'replay'; resourceId: number }
  | { kind: 'error'; status: 400 | 409; message: string };

export function startIdempotentRequest(
  db: Database.Database,
  headers: Record<string, unknown> | undefined,
  scope: string,
  requestHash: string,
): IdempotencyStart {
  let key: string | null;
  try {
    key = normalizeIdempotencyKey(headers?.[IDEMPOTENCY_KEY_HEADER]);
  } catch (err) {
    return { kind: 'error', status: 400, message: (err as Error).message };
  }
  if (!key) return { kind: 'proceed', key: null };
  try {
    const { replayId } = beginIdempotentWrite(db, scope, key, requestHash);
    return replayId !== null
      ? { kind: 'replay', resourceId: replayId }
      : { kind: 'proceed', key };
  } catch (err) {
    if (err instanceof IdempotencyConflictError) {
      return { kind: 'error', status: 409, message: err.message };
    }
    throw err;
  }
}
