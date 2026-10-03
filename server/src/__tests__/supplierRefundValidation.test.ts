/**
 * supplierRefundController request validation.
 *
 * These guards sit in the controller rather than the model so that a bad
 * request is answered 400 instead of surfacing as a 500 from deeper in the
 * stack. The route's zod schema already rejects a non-positive amount, so
 * these tests call the controller directly: the point is to pin the
 * controller's own contract, which holds even if the middleware changes.
 */
import type { Request, Response } from 'express';
import supplierRefundController from '../controllers/supplierRefundController';

/** Minimal Response double capturing the status code and JSON payload. */
interface CapturedResponse {
  statusCode: number;
  body: unknown;
  status: (code: number) => CapturedResponse;
  json: (payload: unknown) => unknown;
}

function capture(): CapturedResponse {
  const captured: CapturedResponse = {
    statusCode: 200,
    body: undefined,
    status(code: number) {
      captured.statusCode = code;
      return captured;
    },
    json(payload: unknown) {
      captured.body = payload;
      return captured;
    },
  };
  return captured;
}

function invoke(body: Record<string, unknown>): CapturedResponse {
  const res = capture();
  const req = {
    body,
    headers: {},
    user: { id: 1 },
  } as unknown as Request & { activityLogged?: boolean };

  // The handler is exported on the controller's default export.
  supplierRefundController.createSupplierRefund(
    req as Parameters<typeof supplierRefundController.createSupplierRefund>[0],
    res as unknown as Response
  );
  return res;
}

describe('createSupplierRefund request validation', () => {
  it('rejects a missing refund_date with 400', () => {
    const res = invoke({ credit_note_id: 1, amount: 100 });
    expect(res.statusCode).toBe(400);
    expect(res.body).toEqual({ error: 'refund_date is required' });
  });

  it('rejects a missing credit_note_id with 400', () => {
    const res = invoke({ refund_date: '2026-07-03', amount: 100 });
    expect(res.statusCode).toBe(400);
    expect(res.body).toEqual({ error: 'A valid credit_note_id is required' });
  });

  it('rejects a missing amount with 400 rather than letting NaN reach the model', () => {
    // Regression guard: Number(undefined) is NaN, which previously slipped
    // past the controller and failed inside the model as a 500.
    const res = invoke({ refund_date: '2026-07-03', credit_note_id: 1 });
    expect(res.statusCode).toBe(400);
    expect(res.body).toEqual({ error: 'A positive amount is required' });
  });

  it('rejects a non-numeric amount with 400', () => {
    const res = invoke({ refund_date: '2026-07-03', credit_note_id: 1, amount: 'abc' });
    expect(res.statusCode).toBe(400);
    expect(res.body).toEqual({ error: 'A positive amount is required' });
  });

  it('rejects a zero or negative amount with 400', () => {
    expect(invoke({ refund_date: '2026-07-03', credit_note_id: 1, amount: 0 }).statusCode).toBe(400);
    expect(invoke({ refund_date: '2026-07-03', credit_note_id: 1, amount: -50 }).statusCode).toBe(400);
  });

  it('rejects an unknown payment_method with 400', () => {
    const res = invoke({
      refund_date: '2026-07-03',
      credit_note_id: 1,
      amount: 100,
      payment_method: 'barter',
    });
    expect(res.statusCode).toBe(400);
    expect(String((res.body as { error: string }).error)).toMatch(/Invalid payment_method/);
  });
});