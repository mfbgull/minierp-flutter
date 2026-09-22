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
export function claimIdempotencyKey(
  db: Database.Database, scope: string, key: string, requestHash: string, resourceId: number,
): void {
  db.prepare(`
    INSERT INTO idempotency_keys (key, scope, request_hash, resource_id, completed_at)
    VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
    ON CONFLICT(key) DO UPDATE SET
      resource_id = excluded.resource_id,
      completed_at = excluded.completed_at
  `).run(key, scope, requestHash, resourceId);
}
