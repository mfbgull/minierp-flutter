import { Response } from 'express';
import logger from './logger';

/**
 * TASK 24 — Centralized business-rule error classification.
 *
 * Business rule violations should return 4xx (especially 409 for state
 * conflicts) rather than generic 500.  This module provides:
 *
 * 1. BusinessRuleError — a typed error that carries its own HTTP status.
 * 2. classifyError() — inspects a thrown value and returns a status + message
 *    if it matches a known business-rule pattern, or null for true server errors.
 * 3. handleBusinessError() — one-liner that classifies + responds.
 */

// ─── BusinessRuleError ───────────────────────────────────────────────

export class BusinessRuleError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
    this.name = 'BusinessRuleError';
  }
}

// ─── Error classification patterns ───────────────────────────────────
//
// Order matters: first match wins.  Each entry is a [regex, status] pair.
// The matched message is forwarded to the client as-is — it is already
// human-readable by construction (thrown from model/service layer).

const CLASSIFY_PATTERNS: [RegExp, number][] = [
  // --- 409 Conflict: state transitions ---
  [/inside closed accounting period/i, 409],
  [/already\s+cancelled/i, 409],
  [/already\s+returned/i, 409],
  [/already\s+voided/i, 409],
  [/already\s+settled/i, 409],
  [/already\s+used/i, 409],                // idempotency
  [/Cannot\s+cancel\s+invoice/i, 409],
  [/Cannot\s+return/i, 409],
  [/Cannot\s+void/i, 409],
  [/is\s+already\s+cancelled/i, 409],
  [/Invoice\s+is\s+already\s+cancelled/i, 409],

  [/refusing\s+to\s+delete/i, 400],
  [/SUPPLIER_REQUIRED_FOR_PURCHASE/i, 400],
  [/insufficient\s+funds/i, 400],
  [/not\s+found/i, 404],
  [/does\s+not\s+exist/i, 404],
];

// ─── Public helpers ──────────────────────────────────────────────────

function isStatusBearingError(error: unknown): error is Error & { status: number } {
  return (
    error instanceof Error &&
    'status' in error &&
    typeof (error as Error & { status: unknown }).status === 'number' &&
    error.name !== 'Error'
  );
}

/**
 * Classify an unknown thrown value into an HTTP status + client message.
 *
 * Returns `{ status, message }` for business-rule violations, or `null`
 * when the error is a genuine server-side failure (should become 500).
 */
export function classifyError(error: unknown): { status: number; message: string } | null {
  // --- Typed error classes that already carry their own status ---
  // ReturnError, BusinessRuleError, etc. — honour the embedded status.
  if (isStatusBearingError(error)) {
    return { status: error.status, message: error.message };
  }

  const msg = error instanceof Error ? error.message : String(error);

  for (const [re, status] of CLASSIFY_PATTERNS) {
    if (re.test(msg)) {
      return { status, message: msg };
    }
  }

  return null; // genuine server error → caller should respond 500
}

/**
 * Classify + respond in one call. Always sends exactly one response:
 *  - business-rule violation → classified status + the service's own message
 *  - genuine server error → 500 with `fallbackMessage` (detail stays server-side)
 * Pass `opts: { success: true }` for controllers whose API shape is
 * `{ success: false, error }` instead of the bare `{ error }`.
 */
export function handleBusinessError(
  res: Response,
  error: unknown,
  context: string,
  fallbackMessage = 'Internal server error',
  opts?: { success?: boolean },
): void {
  const send = (status: number, payload: Record<string, unknown>) => {
    if (opts?.success) {
      res.status(status).json({ success: false, ...payload });
    } else {
      res.status(status).json(payload);
    }
  };

  const classified = classifyError(error);

  if (classified) {
    logger.warn(`${context} — business rule violation: ${classified.message}`);
    send(classified.status, { error: classified.message });
    return;
  }

  // Genuine server error — log full details, return safe message.
  const msg = error instanceof Error ? error.message : fallbackMessage;
  const stack = error instanceof Error ? error.stack : undefined;
  logger.error(`${context}:`, { error: msg, stack });
  send(500, { error: fallbackMessage });
}
