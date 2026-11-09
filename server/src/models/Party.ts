import type Database from 'better-sqlite3';
import type { z } from 'zod';
import CustomerModel from './Customer';
import SupplierModel from './Supplier';
import { BusinessRuleError } from '../utils/businessRuleError';
import { getNextSequenceNumber, initializeSequenceFromMax } from '../utils/sequence';
import { localMonthCode } from '../utils/documentNumbering';
import { roundCurrency } from '../utils/currency';
import type { PartyPosition, PartyRole, PartyTargets, PartyTarget, PartyPayableTarget, partyCustomerInput, partySupplierInput } from '../types/party';

type RoleRow = PartyRole & { readonly party_id: number; readonly current_balance: number; readonly credit_balance: number };

export class PartyModel {
  constructor(private readonly db: Database.Database) {}

  roles(partyId: number): { display_name: string; customer: RoleRow | null; supplier: RoleRow | null } {
    const party = this.db.prepare<[number], { display_name: string }>('SELECT display_name FROM parties WHERE id=?').get(partyId);
    if (!party) throw new BusinessRuleError(404, 'Party not found');
    const customer = this.db.prepare<[number], RoleRow>(`SELECT id,party_id,customer_code AS code,customer_name AS name,
      is_active,current_balance,COALESCE(credit_balance,0) AS credit_balance FROM customers WHERE party_id=? AND deleted_at IS NULL`).get(partyId) ?? null;
    const supplier = this.db.prepare<[number], RoleRow>(`SELECT id,party_id,supplier_code AS code,supplier_name AS name,
      is_active,current_balance,0 AS credit_balance FROM suppliers WHERE party_id=?`).get(partyId) ?? null;
    return { display_name: party.display_name, customer, supplier };
  }

  position(partyId: number): PartyPosition {
    const roles = this.roles(partyId);
    const targets = this.targets(partyId);
    const receivables = roundCurrency(targets.receivables.reduce((sum, row) => sum + row.balance_amount, 0));
    const payables = roundCurrency(targets.payables.reduce((sum, row) => sum + row.balance_amount, 0));
    const customerBalance = roles.customer?.current_balance ?? 0;
    const supplierBalance = roles.supplier?.current_balance ?? 0;
    return { id: partyId, ...roles, customer_balance: customerBalance, supplier_balance: supplierBalance,
      net_balance: roundCurrency(customerBalance - supplierBalance), customer_credit: roles.customer?.credit_balance ?? 0,
      supplier_advance: this.supplierAdvance(roles.supplier?.id), eligible_receivables: receivables,
      eligible_payables: payables, maximum_adjustment: this.maximumAdjustment(roles, receivables, payables) };
  }

  private supplierAdvance(supplierId: number | undefined): number {
    if (!supplierId) return 0;
    const row = this.db.prepare<[number], { amount: number }>(`SELECT COALESCE(SUM(a.amount - COALESCE((
      SELECT SUM(x.amount) FROM supplier_prepayment_applications x JOIN payments p ON p.id=x.payment_id
      WHERE x.prepayment_id=a.id AND p.voided_at IS NULL),0)),0) AS amount
      FROM supplier_prepayments a WHERE a.supplier_id=? AND a.voided_at IS NULL`).get(supplierId);
    return roundCurrency(row?.amount ?? 0);
  }

  private maximumAdjustment(roles: { customer: RoleRow | null; supplier: RoleRow | null }, receivables: number, payables: number): number {
    if (!roles.customer?.is_active || !roles.supplier?.is_active) return 0;
    return Math.min(receivables, payables);
  }

  targets(partyId: number): PartyTargets {
    const { customer, supplier } = this.roles(partyId);
    const receivables = customer ? this.db.prepare<[number], PartyTarget>(`SELECT id,invoice_no AS reference,
      invoice_date AS date,balance_amount FROM invoices
      WHERE customer_id=? AND deleted_at IS NULL
        AND LOWER(status) NOT IN ('cancelled','draft','deleted') AND balance_amount>0
      ORDER BY invoice_date,id`).all(customer.id) : [];
    const payables = supplier ? this.db.prepare<[number,number,number], PartyPayableTarget>(`
      SELECT * FROM (
        SELECT 'purchase' AS kind,p.id,p.purchase_no AS reference,p.purchase_date AS date,
          ROUND(v.total_payable-v.returned_amount-v.settled_amount,2) AS balance_amount
        FROM purchases p JOIN direct_purchase_payables v ON v.id=p.id
        WHERE p.supplier_id=? AND p.voided_at IS NULL
        UNION ALL
        SELECT 'purchase_order',po.id,po.po_no,recognized.date,
          ROUND(recognized.amount-v.returned_amount-v.settled_amount,2)
        FROM purchase_orders po JOIN purchase_order_payables v ON v.id=po.id
        JOIN (SELECT gr.po_id,MAX(gr.receipt_date) AS date,SUM(jl.credit-jl.debit) AS amount
          FROM goods_receipts gr JOIN journal_lines jl ON jl.reference_type='GOODS_RECEIPT' AND jl.reference_id=gr.id
          JOIN chart_of_accounts a ON a.id=jl.account_id AND a.code='2000'
          WHERE jl.voided=0 GROUP BY gr.po_id) recognized ON recognized.po_id=po.id
        WHERE po.supplier_id=? AND LOWER(po.status)<>'cancelled'
        UNION ALL
        SELECT 'supplier_bill',b.id,b.bill_no,b.bill_date,
          ROUND(b.total_amount-COALESCE((SELECT SUM(a.amount) FROM supplier_bill_allocations a
            JOIN payments p ON p.id=a.payment_id WHERE a.bill_id=b.id AND a.voided_at IS NULL AND p.voided_at IS NULL),0)
            -COALESCE((SELECT SUM(a.amount) FROM party_adjustment_payables a JOIN party_adjustments j ON j.id=a.adjustment_id
              WHERE a.bill_id=b.id AND j.status='posted'),0),2)
        FROM supplier_bills b WHERE b.supplier_id=? AND b.voided_at IS NULL
      ) WHERE balance_amount>0 ORDER BY date,id
    `).all(supplier.id,supplier.id,supplier.id) : [];
    return { receivables, payables };
  }

  link(customerId: number, supplierId: number, userId: number): PartyPosition {
    return this.db.transaction(() => {
      const customer = this.db.prepare<[number], { party_id: number }>('SELECT party_id FROM customers WHERE id=? AND is_active=1 AND deleted_at IS NULL').get(customerId);
      const supplier = this.db.prepare<[number], { party_id: number }>('SELECT party_id FROM suppliers WHERE id=? AND is_active=1').get(supplierId);
      if (!customer || !supplier) throw new BusinessRuleError(404, 'Customer or supplier not found');
      if (customer.party_id === supplier.party_id) return this.position(customer.party_id);
      if (this.roles(customer.party_id).supplier || this.roles(supplier.party_id).customer) throw new BusinessRuleError(409, 'A profile already has a linked role');
      this.assertNoHistory(customer.party_id, supplier.party_id);
      this.db.prepare('UPDATE suppliers SET party_id=? WHERE id=?').run(customer.party_id,supplierId);
      this.recordIdentityEvent(customer.party_id,customerId,supplierId,'link',supplier.party_id,userId);
      return this.position(customer.party_id);
    }).immediate();
  }

  unlink(partyId: number, userId: number): PartyPosition {
    return this.db.transaction(() => {
      const roles = this.roles(partyId);
      if (!roles.customer || !roles.supplier) throw new BusinessRuleError(409,'Party does not have both roles');
      this.assertNoHistory(partyId,partyId);
      const newParty = Number(this.db.prepare('INSERT INTO parties(display_name) VALUES (?)').run(roles.supplier.name).lastInsertRowid);
      this.db.prepare('UPDATE suppliers SET party_id=? WHERE id=?').run(newParty,roles.supplier.id);
      this.recordIdentityEvent(partyId,roles.customer.id,roles.supplier.id,'unlink',newParty,userId);
      return this.position(partyId);
    }).immediate();
  }

  addCustomer(partyId: number, input: z.infer<typeof partyCustomerInput>, userId: number): PartyPosition {
    return this.db.transaction(() => {
      if (this.roles(partyId).customer) throw new BusinessRuleError(409,'Party already has a customer role');
      initializeSequenceFromMax(this.db,'CUST_last_no','customers','customer_code','CUST');
      const code = `CUST-${localMonthCode(new Date())}-${String(getNextSequenceNumber(this.db,'CUST_last_no')).padStart(5,'0')}`;
      const id = CustomerModel.create(input,this.db);
      const autoParty = this.db.prepare<[number], { party_id: number }>('SELECT party_id FROM customers WHERE id=?').get(id)?.party_id;
      CustomerModel.updateCode(id,code,this.db);
      this.db.prepare('UPDATE customers SET party_id=? WHERE id=?').run(partyId,id);
      if (autoParty && autoParty !== partyId) this.deleteOrphanParty(autoParty);
      this.recordIdentityEvent(partyId,id,null,'add_customer',null,userId);
      return this.position(partyId);
    }).immediate();
  }

  addSupplier(partyId: number, input: z.infer<typeof partySupplierInput>, userId: number): PartyPosition {
    return this.db.transaction(() => {
      if (this.roles(partyId).supplier) throw new BusinessRuleError(409,'Party already has a supplier role');
      if (this.db.prepare('SELECT id FROM suppliers WHERE supplier_code=?').get(input.supplier_code)) throw new BusinessRuleError(409,'Supplier code already exists');
      const id = SupplierModel.create(input,this.db);
      const autoParty = this.db.prepare<[number], { party_id: number }>('SELECT party_id FROM suppliers WHERE id=?').get(id)?.party_id;
      this.db.prepare('UPDATE suppliers SET party_id=? WHERE id=?').run(partyId,id);
      if (autoParty && autoParty !== partyId) this.deleteOrphanParty(autoParty);
      this.recordIdentityEvent(partyId,null,id,'add_supplier',null,userId);
      return this.position(partyId);
    }).immediate();
  }

  private assertNoHistory(first: number, second: number): void {
    if (this.db.prepare('SELECT id FROM party_adjustments WHERE party_id IN (?,?) LIMIT 1').get(first,second))
      throw new BusinessRuleError(409,'Adjustment history prevents changing this identity link');
  }

  private recordIdentityEvent(partyId: number, customerId: number | null, supplierId: number | null, action: string, previous: number | null, userId: number): void {
    this.db.prepare(`INSERT INTO party_identity_events(party_id,customer_id,supplier_id,action,previous_party_id,created_by)
      VALUES (?,?,?,?,?,?)`).run(partyId,customerId,supplierId,action,previous,userId);
  }

  private deleteOrphanParty(partyId: number): void {
    const used = this.db.prepare(`SELECT 1 FROM customers WHERE party_id=?
      UNION ALL SELECT 1 FROM suppliers WHERE party_id=?
      UNION ALL SELECT 1 FROM party_adjustments WHERE party_id=?
      UNION ALL SELECT 1 FROM party_identity_events WHERE party_id=? OR previous_party_id=?
      LIMIT 1`).get(partyId,partyId,partyId,partyId,partyId);
    if (!used) this.db.prepare('DELETE FROM parties WHERE id=?').run(partyId);
  }
}
