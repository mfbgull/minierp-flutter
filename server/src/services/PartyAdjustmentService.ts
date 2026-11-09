import type Database from 'better-sqlite3';
import { PartyModel } from '../models/Party';
import SupplierLedgerModel from '../models/SupplierLedger';
import AccountingService from './accountingService';
import ledgerUtils from '../utils/ledgerUtils';
import { BusinessRuleError } from '../utils/businessRuleError';
import { claimIdempotencyKey, hashRequestPayload, startIdempotentRequest } from '../utils/idempotency';
import { getNextSequenceNumber } from '../utils/sequence';
import { roundCurrency } from '../utils/currency';
import { partyAdjustmentInput, partyReversalInput } from '../types/party';
import type { PartyAdjustment, PartyAdjustmentDetail, PartyAdjustmentInput, PartyPayableTarget, PartyTargets } from '../types/party';

type Headers = Record<string,string | string[] | undefined>;
const SCOPE = 'party-adjustments.create';

export class PartyAdjustmentService {
  constructor(private readonly db: Database.Database) {}

  get(partyId: number, id: number): PartyAdjustmentDetail {
    const row = this.db.prepare<[number,number], PartyAdjustment>('SELECT * FROM party_adjustments WHERE party_id=? AND id=?').get(partyId,id);
    if (!row) throw new BusinessRuleError(404,'Adjustment not found');
    const receivables = this.db.prepare<[number], { invoice_id: number; reference: string; amount: number }>(`
      SELECT a.invoice_id,i.invoice_no AS reference,a.amount FROM party_adjustment_receivables a
      JOIN invoices i ON i.id=a.invoice_id WHERE a.adjustment_id=? ORDER BY a.id`).all(id);
    const payables = this.db.prepare<[number], { kind: PartyPayableTarget['kind']; id: number; reference: string; amount: number }>(`
      SELECT CASE WHEN a.purchase_id IS NOT NULL THEN 'purchase' WHEN a.purchase_order_id IS NOT NULL THEN 'purchase_order' ELSE 'supplier_bill' END AS kind,
        COALESCE(a.purchase_id,a.purchase_order_id,a.bill_id) AS id,COALESCE(p.purchase_no,po.po_no,b.bill_no) AS reference,a.amount
      FROM party_adjustment_payables a LEFT JOIN purchases p ON p.id=a.purchase_id
      LEFT JOIN purchase_orders po ON po.id=a.purchase_order_id LEFT JOIN supplier_bills b ON b.id=a.bill_id
      WHERE a.adjustment_id=? ORDER BY a.id`).all(id);
    return { ...row,receivables,payables };
  }

  list(partyId: number, page: number, limit: number): { data: PartyAdjustment[]; total: number } {
    new PartyModel(this.db).roles(partyId);
    const data = this.db.prepare<[number,number,number], PartyAdjustment>(`SELECT * FROM party_adjustments
      WHERE party_id=? ORDER BY adjustment_date DESC,id DESC LIMIT ? OFFSET ?`).all(partyId,limit,(page-1)*limit);
    const total = this.db.prepare<[number], { total: number }>('SELECT COUNT(*) AS total FROM party_adjustments WHERE party_id=?').get(partyId)?.total ?? 0;
    return { data,total };
  }

  postAdjustment(partyId: number, body: unknown, userId: number, headers: Headers): PartyAdjustmentDetail {
    const parsed = partyAdjustmentInput.safeParse(body);
    if (!parsed.success) throw new BusinessRuleError(400,parsed.error.issues[0]?.message ?? 'Invalid adjustment');
    const input = parsed.data;
    return this.db.transaction(() => {
      const hash = hashRequestPayload({ partyId,...input });
      const start = startIdempotentRequest(this.db,headers,SCOPE,hash);
      if (start.kind === 'error') throw new BusinessRuleError(start.status,start.message);
      if (start.kind === 'replay') return this.get(partyId,start.resourceId);
      if (!start.key) throw new BusinessRuleError(400,'Idempotency-Key is required');
      const party = new PartyModel(this.db);
      const { customer,supplier } = party.roles(partyId);
      if (!customer?.is_active || !supplier?.is_active) throw new BusinessRuleError(409,'An active customer and supplier role are required');
      AccountingService.assertPeriodNotClosed(this.db,input.adjustment_date,'Party adjustment');
      this.validateAllocations(input,party.targets(partyId));
      const adjustmentNo = `ADJ-${String(getNextSequenceNumber(this.db,'PARTY_ADJUSTMENT_last_no')).padStart(6,'0')}`;
      const id = Number(this.db.prepare(`INSERT INTO party_adjustments
        (adjustment_no,party_id,customer_id,supplier_id,adjustment_date,amount,notes,created_by)
        VALUES (?,?,?,?,?,?,?,?)`).run(adjustmentNo,partyId,customer.id,supplier.id,input.adjustment_date,input.amount,input.notes ?? null,userId).lastInsertRowid);
      this.insertAllocations(id,input);
      this.postAccounting(id,adjustmentNo,customer.id,supplier.id,input,userId);
      this.recalculate(customer.id,supplier.id,input.receivables.map(row=>row.invoice_id));
      this.recordActivity(id,userId,'PARTY_ADJUSTMENT_CREATE',`Posted ${adjustmentNo}`);
      claimIdempotencyKey(this.db,SCOPE,start.key,hash,id);
      return this.get(partyId,id);
    }).immediate();
  }

  reverseAdjustment(partyId: number, id: number, body: unknown, userId: number): PartyAdjustmentDetail {
    const parsed = partyReversalInput.safeParse(body);
    if (!parsed.success) throw new BusinessRuleError(400,parsed.error.issues[0]?.message ?? 'Invalid reversal');
    const { reason,reversal_date: date } = parsed.data;
    return this.db.transaction(() => {
      const source = this.get(partyId,id);
      if (source.status === 'reversed') throw new BusinessRuleError(409,'Adjustment is already reversed');
      if (date < source.adjustment_date) throw new BusinessRuleError(400,'Reversal cannot precede the adjustment');
      AccountingService.assertPeriodNotClosed(this.db,source.adjustment_date,'Party adjustment reversal');
      AccountingService.assertPeriodNotClosed(this.db,date,'Party adjustment reversal');
      this.db.prepare(`UPDATE party_adjustments SET status='reversed',reversed_by=?,reversed_at=CURRENT_TIMESTAMP,
        reversal_date=?,reversal_reason=? WHERE id=?`).run(userId,date,reason,id);
      this.assertReturnSettlementsRemainCovered(source.receivables.map(row=>row.invoice_id));
      this.reverseSubledgers(source,date,reason);
      AccountingService.voidJournalLinesByReference(this.db,'PARTY_ADJUSTMENT',id,{ voidedBy:userId,voidReason:reason });
      this.recalculate(source.customer_id,source.supplier_id,source.receivables.map(row=>row.invoice_id));
      this.recordActivity(id,userId,'PARTY_ADJUSTMENT_REVERSE',`Reversed ${source.adjustment_no}: ${reason}`);
      return this.get(partyId,id);
    }).immediate();
  }

  private validateAllocations(input: PartyAdjustmentInput, targets: PartyTargets): void {
    const invoices = new Map(targets.receivables.map(row=>[row.id,row]));
    const payables = new Map(targets.payables.map(row=>[`${row.kind}:${row.id}`,row]));
    const seen = new Set<string>();
    for (const row of input.receivables) {
      this.checkTarget(`invoice:${row.invoice_id}`,row.amount,invoices.get(row.invoice_id),input.adjustment_date,seen);
    }
    for (const row of input.payables) {
      const key = `${row.kind}:${row.id}`;
      this.checkTarget(key,row.amount,payables.get(key),input.adjustment_date,seen);
    }
    const cents = Math.round(input.amount*100);
    if (input.receivables.reduce((sum,row)=>sum+Math.round(row.amount*100),0)!==cents ||
        input.payables.reduce((sum,row)=>sum+Math.round(row.amount*100),0)!==cents)
      throw new BusinessRuleError(400,'Both allocation totals must equal the adjustment amount');
  }

  private checkTarget(key: string, amount: number, target: { date: string; balance_amount: number } | undefined, date: string, seen: Set<string>): void {
    if (seen.has(key)) throw new BusinessRuleError(400,'Select each document only once');
    seen.add(key);
    if (!target) throw new BusinessRuleError(400,'Selected document is not outstanding for this Party');
    if (date < target.date) throw new BusinessRuleError(400,'Adjustment cannot precede a selected document');
    if (Math.round(amount*100)>Math.round(target.balance_amount*100)) throw new BusinessRuleError(400,'Adjustment exceeds the current outstanding balance. Refresh the documents');
  }

  private insertAllocations(id: number, input: PartyAdjustmentInput): void {
    const receivable = this.db.prepare('INSERT INTO party_adjustment_receivables(adjustment_id,invoice_id,amount) VALUES (?,?,?)');
    for (const row of input.receivables) receivable.run(id,row.invoice_id,row.amount);
    const payable = this.db.prepare(`INSERT INTO party_adjustment_payables(adjustment_id,purchase_id,purchase_order_id,bill_id,amount) VALUES (?,?,?,?,?)`);
    for (const row of input.payables) {
      switch (row.kind) {
        case 'purchase': payable.run(id,row.id,null,null,row.amount); break;
        case 'purchase_order': payable.run(id,null,row.id,null,row.amount); break;
        case 'supplier_bill': payable.run(id,null,null,row.id,row.amount); break;
      }
    }
  }

  private postAccounting(id: number, reference: string, customerId: number, supplierId: number, input: PartyAdjustmentInput, userId: number): void {
    const ar = AccountingService.getAccountByCode(this.db,'1100');
    if (!ar) throw new BusinessRuleError(409,'Required receivable account is missing');
    const debits = this.payableDebits(input);
    AccountingService.postEntry(this.db,{ entry_date:input.adjustment_date,reference_type:'PARTY_ADJUSTMENT',reference_id:id,
      description:`Noncash adjustment ${reference}`,created_by:userId,
      lines:[...[...debits].map(([account_id,debit])=>({ account_id,debit })),
        { account_id:ar.id,credit:input.amount }] });
    ledgerUtils.createLedgerEntry(customerId,input.adjustment_date,'PARTY_ADJUSTMENT',reference,0,input.amount,`Noncash adjustment ${reference}`,this.db);
    SupplierLedgerModel.createEntry({ supplier_id:supplierId,transaction_date:input.adjustment_date,
      transaction_type:'PARTY_ADJUSTMENT',reference_no:reference,credit:input.amount,description:`Noncash adjustment ${reference}` },this.db);
  }

  private payableDebits(input: PartyAdjustmentInput): Map<number, number> {
    const fallback = AccountingService.getAccountByCode(this.db,'2000');
    if (!fallback) throw new BusinessRuleError(409,'Required payable account is missing');
    const debits = new Map<number, number>();
    for (const row of input.payables) {
      const accountId = this.payableAccount(row) ?? fallback.id;
      debits.set(accountId,roundCurrency((debits.get(accountId) ?? 0) + row.amount));
    }
    return debits;
  }

  private payableAccount(row: PartyAdjustmentInput['payables'][number]): number | undefined {
    if (row.kind === 'purchase') return this.creditAccount('PURCHASE',row.id);
    if (row.kind === 'supplier_bill') return this.creditAccount('SUPPLIER_BILL',row.id);
    const receipt = this.db.prepare<[number], { account_id: number }>(`
      SELECT jl.account_id FROM journal_lines jl
      JOIN goods_receipts gr ON gr.id = jl.reference_id
      WHERE jl.reference_type='GOODS_RECEIPT' AND gr.po_id=? AND jl.voided=0 AND jl.credit>0
      GROUP BY jl.account_id ORDER BY SUM(jl.credit) DESC LIMIT 1`).get(row.id);
    return receipt?.account_id;
  }

  private creditAccount(referenceType: string, referenceId: number): number | undefined {
    const row = this.db.prepare<[string, number], { account_id: number }>(`
      SELECT account_id FROM journal_lines
      WHERE reference_type=? AND reference_id=? AND voided=0 AND credit>0
      GROUP BY account_id ORDER BY SUM(credit) DESC LIMIT 1`).get(referenceType,referenceId);
    return row?.account_id;
  }

  private reverseSubledgers(source: PartyAdjustment, date: string, reason: string): void {
    const customer = this.db.prepare<[number,string], { id: number }>(`SELECT id FROM customer_ledger
      WHERE customer_id=? AND transaction_type='PARTY_ADJUSTMENT' AND reference_no=? AND voided=0`).get(source.customer_id,source.adjustment_no);
    const supplier = this.db.prepare<[number,string], { id: number }>(`SELECT id FROM supplier_ledger
      WHERE supplier_id=? AND transaction_type='PARTY_ADJUSTMENT' AND reference_no=? AND voided=0`).get(source.supplier_id,source.adjustment_no);
    if (!customer || !supplier) throw new BusinessRuleError(409,'Adjustment ledger entries are missing');
    this.db.prepare(`INSERT INTO customer_ledger(customer_id,transaction_date,transaction_type,reference_no,debit,credit,balance,description,reversed_by)
      VALUES (?,?,'REVERSAL:PARTY_ADJUSTMENT',?,?,0,0,?,?)`).run(source.customer_id,date,source.adjustment_no,source.amount,reason,customer.id);
    this.db.prepare('UPDATE customer_ledger SET voided=1 WHERE id=?').run(customer.id);
    this.db.prepare(`INSERT INTO supplier_ledger(supplier_id,transaction_date,transaction_type,reference_no,debit,credit,balance,description,reversed_by)
      VALUES (?,?,'REVERSAL:PARTY_ADJUSTMENT',?,?,0,0,?,?)`).run(source.supplier_id,date,source.adjustment_no,source.amount,reason,supplier.id);
    this.db.prepare('UPDATE supplier_ledger SET voided=1 WHERE id=?').run(supplier.id);
  }

  private assertReturnSettlementsRemainCovered(invoiceIds: readonly number[]): void {
    for (const invoiceId of invoiceIds) {
      const row = this.db.prepare<[number], { covered: number; settled: number }>(`SELECT
        MAX(0,i.paid_amount + COALESCE((SELECT SUM(a.amount) FROM party_adjustment_receivables a
          JOIN party_adjustments j ON j.id=a.adjustment_id WHERE a.invoice_id=i.id AND j.status='posted'),0)
          - (i.total_amount-COALESCE(i.returned_amount,0)+COALESCE(i.return_fee,0))) AS covered,
        COALESCE((SELECT SUM(s.amount) FROM return_settlements s JOIN invoice_returns r ON r.id=s.return_id
          WHERE r.invoice_id=i.id AND s.voided_at IS NULL),0) AS settled
        FROM invoices i WHERE i.id=?`).get(invoiceId);
      if (row && roundCurrency(row.settled)>roundCurrency(row.covered))
        throw new BusinessRuleError(409,'Reverse dependent return settlements before reversing this adjustment');
    }
  }

  private recalculate(customerId: number, supplierId: number, invoiceIds: readonly number[]): void {
    for (const invoiceId of invoiceIds) {
      ledgerUtils.calculateInvoiceBalance(invoiceId,this.db);
      ledgerUtils.updateInvoiceStatus(invoiceId,this.db);
    }
    ledgerUtils.rebuildLedgerBalances(customerId,this.db);
    ledgerUtils.recalcCustomerBalanceFromLedger(customerId,this.db);
    SupplierLedgerModel.rebuildBalances(supplierId,this.db);
  }

  private recordActivity(id: number, userId: number, action: string, description: string): void {
    this.db.prepare(`INSERT INTO activity_log(user_id,action,entity_type,entity_id,description)
      VALUES (?,?,'PartyAdjustment',?,?)`).run(userId,action,id,description);
  }
}
