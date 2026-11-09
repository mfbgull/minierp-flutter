import { z } from 'zod';

const id = z.number().int().positive();
const money = z.number().finite().positive().max(1e9).refine(value => Math.abs(value * 100 - Math.round(value * 100)) < 0.00001, 'Use at most two decimal places');
export const partyDate = z.iso.date();
export const partyAdjustmentInput = z.object({
  adjustment_date: partyDate,
  amount: money,
  notes: z.string().trim().max(1000).optional(),
  receivables: z.array(z.object({ invoice_id: id, amount: money })).min(1).max(100),
  payables: z.array(z.object({ kind: z.enum(['purchase', 'purchase_order', 'supplier_bill']), id, amount: money })).min(1).max(100),
});
export type PartyAdjustmentInput = z.infer<typeof partyAdjustmentInput>;
export const partyLinkInput = z.object({ customer_id: id, supplier_id: id, confirmed: z.literal(true) });
export const partyReversalInput = z.object({ reason: z.string().trim().min(1).max(1000), reversal_date: partyDate });
const contact = { contact_person: z.string().max(200).optional(), email: z.string().max(200).optional(),
  phone: z.string().max(100).optional(), payment_terms: z.string().max(200).optional() };
export const partyCustomerInput = z.object({ ...contact, customer_name: z.string().trim().min(1).max(200),
  phone: z.string().trim().min(1).max(100), billing_address: z.string().max(1000).optional(),
  shipping_address: z.string().max(1000).optional(), payment_terms_days: z.number().int().nonnegative().optional(),
  credit_limit: z.number().finite().nonnegative().optional(), opening_balance: z.literal(0).optional() });
export const partySupplierInput = z.object({ ...contact, supplier_code: z.string().trim().min(1).max(100),
  supplier_name: z.string().trim().min(1).max(200), address: z.string().max(1000).optional() });
export type PartyRole = { readonly id: number; readonly code: string; readonly name: string; readonly is_active: number };
export type PartyTarget = { readonly id: number; readonly reference: string; readonly date: string; readonly balance_amount: number };
export type PartyPayableTarget = PartyTarget & { readonly kind: 'purchase' | 'purchase_order' | 'supplier_bill' };
export type PartyTargets = { readonly receivables: readonly PartyTarget[]; readonly payables: readonly PartyPayableTarget[] };
export type PartyPosition = {
  readonly id: number; readonly display_name: string; readonly customer: PartyRole | null; readonly supplier: PartyRole | null;
  readonly customer_balance: number; readonly supplier_balance: number; readonly net_balance: number;
  readonly customer_credit: number; readonly supplier_advance: number;
  readonly eligible_receivables: number; readonly eligible_payables: number; readonly maximum_adjustment: number;
};
export type PartyAdjustment = {
  readonly id: number; readonly adjustment_no: string; readonly party_id: number; readonly customer_id: number;
  readonly supplier_id: number; readonly adjustment_date: string; readonly amount: number; readonly notes: string | null;
  readonly status: 'posted' | 'reversed'; readonly created_by: number; readonly created_at: string;
  readonly reversed_by: number | null; readonly reversed_at: string | null;
  readonly reversal_date: string | null; readonly reversal_reason: string | null;
};
export type PartyAdjustmentDetail = PartyAdjustment & {
  readonly receivables: readonly { invoice_id: number; reference: string; amount: number }[];
  readonly payables: readonly { kind: PartyPayableTarget['kind']; id: number; reference: string; amount: number }[];
};
