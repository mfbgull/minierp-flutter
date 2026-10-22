import type { ProcessReturnInput, SettlementInput } from '../services/invoiceReturnService';
import type { FeeType } from '../services/returnMath';

type ReturnOptions = Omit<ProcessReturnInput, 'invoiceId' | 'items' | 'userId' | 'reason'>;

export function invoiceReturnOptions(body: Record<string, unknown>): ReturnOptions {
  return {
    feeType: (body.fee_type as FeeType | undefined) ?? undefined,
    feeValue: body.fee_value !== undefined ? Number(body.fee_value) : undefined,
    returnDate: body.return_date ? String(body.return_date) : null,
    warehouseId: body.warehouse_id === undefined || body.warehouse_id === null || body.warehouse_id === ''
      ? null : Number(body.warehouse_id),
    settlements: Array.isArray(body.settlements) && body.settlements.length > 0
      ? (body.settlements as SettlementInput[]) : null,
    ...legacyReturnOptions(body),
  };
}

function legacyReturnOptions(body: Record<string, unknown>): ReturnOptions {
  return {
    disposition: (body.disposition as 'refund' | 'credit' | 'adjust' | null) ?? null,
    adjustInvoiceIds: Array.isArray(body.adjust_invoice_ids) ? (body.adjust_invoice_ids as number[]) : null,
    deductionType: (body.deduction_type as 'fixed' | 'percentage' | 'flat' | null) ?? null,
    deductionValue: body.deduction_value !== undefined ? Number(body.deduction_value) : undefined,
  };
}
