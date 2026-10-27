import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { createCustomer, createInvoice, createItem, getAuthCookie, processReturn, purchaseStock } from './helpers/invoiceReturnSpec';
import { expectAllInvariantsHold } from './helpers/accountingInvariants';

describe('salary recognition, chronology and D15', () => {
  let cookie: string;
  let employee: number;
  afterAll(() => {
    expectAllInvariantsHold('audited salary/chronology/D15 fixture', db);
    expect(db.prepare(`SELECT journal_entry_id FROM journal_lines WHERE voided=0 GROUP BY journal_entry_id
      HAVING ABS(SUM(debit-credit))>0.005`).all()).toEqual([]);
  });
  beforeAll(async () => {
    cookie = await getAuthCookie();
    expect((await post('/api/owner-equity/capital', { amount: 10000, capital_date: '2026-01-01', payment_method: 'Bank' })).status).toBe(201);
    const res = await post('/api/employees', { employee_code: 'REMEDIATION', first_name: 'Audit', last_name: 'Payroll', salary: 1000 });
    expect(res.status).toBe(201);
    employee = res.body.data.id;
  });
  async function post(url: string, body: object) { return request(app).post(url).set('Cookie', cookie).send(body); }
  function net(code: string) {
    return Math.round((db.prepare(`SELECT COALESCE(SUM(j.debit-j.credit),0) AS n FROM journal_lines j
      JOIN chart_of_accounts a ON a.id=j.account_id WHERE a.code=? AND j.voided=0`).get(code) as { n: number }).n * 100);
  }
  it('F-020 earns the advance once and reverses recognition before releasing its source', async () => {
    const first = await post(`/api/employees/${employee}/salary/pay`, { amount: 1200, payment_date: '2026-08-20', payment_method: 'Bank', payment_type: 'partial' });
    expect(first.status).toBe(201);
    expect(net('6100')).toBe(100000);
    expect(net('1310')).toBe(20000);
    const second = await post(`/api/employees/${employee}/salary/pay`, { amount: 800, payment_date: '2026-09-20', payment_method: 'Bank', payment_type: 'full' });
    expect(second.status).toBe(201);
    expect(net('6100')).toBe(200000);
    expect(net('1310')).toBe(0);
    expect(net('1010')).toBe(800000);
    const blocked = await request(app).delete(`/api/employees/${employee}/salary/${first.body.data.id}`).set('Cookie', cookie);
    expect(blocked.status).toBe(409);
    const reversed = await request(app).delete(`/api/employees/${employee}/salary/${second.body.data.id}`).set('Cookie', cookie);
    expect(reversed.status).toBe(204);
    expect(net('6100')).toBe(100000);
    expect(net('1310')).toBe(20000);
    expect((await request(app).delete(`/api/employees/${employee}/salary/${first.body.data.id}`).set('Cookie', cookie)).status).toBe(204);
    expect(net('6100')).toBe(0);
    expect(net('1310')).toBe(0);
    expect(net('1010')).toBe(1000000);
  });
  it('F-043 explains all salary expense in report category rows', async () => {
    const paid = await post(`/api/employees/${employee}/salary/pay`, { amount: 100, payment_date: '2026-10-20', payment_method: 'Bank', payment_type: 'partial' });
    expect(paid.status).toBe(201);
    const report = await request(app).get('/api/reports/profit-loss?fromDate=2026-10-01&toDate=2026-10-31').set('Cookie', cookie);
    expect(report.status).toBe(200);
    const data = report.body.data;
    expect(data.totalExpenses).toBe(100);
    const categories = data.expenses as Array<{ total: number }>;
    expect(categories.reduce((sum, row) => sum + Math.round(row.total * 100), 0)).toBe(10000);
  });
  it('rejects sub-cent salary at the employee write boundary', async () => {
    const created = await post('/api/employees', { employee_code: 'SUB-CENT', first_name: 'Invalid', last_name: 'Salary', salary: 0.001 });
    expect(created.status).toBe(422);
    expect(db.prepare("SELECT id FROM employees WHERE first_name='Invalid' AND last_name='Salary'").get()).toBeUndefined();
  });
  it('F-020 recognizes a large advance over two months, including a zero-cash payroll', async () => {
    const created = await post('/api/employees', { employee_code: 'MULTI-CARRY', first_name: 'Multi', last_name: 'Carry', salary: 1000 });
    expect(created.status).toBe(201);
    const id = created.body.data.id;
    const bank = net('1010');
    const wages = net('6100');
    expect((await post(`/api/employees/${id}/salary/pay`, { amount: 2500, payment_date: '2026-08-20', payment_method: 'Bank', payment_type: 'partial' })).status).toBe(201);
    const september = await post(`/api/employees/${id}/salary/pay`, { amount: 0, payment_date: '2026-09-20', payment_method: 'Bank', payment_type: 'full' });
    expect(september.status).toBe(201);
    expect(net('6100') - wages).toBe(200000);
    expect(net('1310')).toBe(50000);
    expect(net('1010') - bank).toBe(-250000);
    expect((await post(`/api/employees/${id}/salary/pay`, { amount: 500, payment_date: '2026-10-20', payment_method: 'Bank', payment_type: 'full' })).status).toBe(201);
    expect(net('6100') - wages).toBe(300000);
    expect(net('1310')).toBe(0);
    expect(net('1010') - bank).toBe(-300000);
  });
  it('F-021 rejects a repayment before disbursement without a historical loan credit', async () => {
    const loan = await post(`/api/employees/${employee}/loans`, { amount: 500, disbursement_date: '2026-09-15', payment_method: 'Bank' });
    expect(loan.status).toBe(201);
    const before = db.prepare('SELECT * FROM journal_lines ORDER BY id').all();
    const repay = await post(`/api/employees/${employee}/loans/${loan.body.data.id}/repay`, { amount: 200, payment_date: '2026-09-01', payment_method: 'Bank' });
    expect(repay.status).toBe(400);
    expect(db.prepare('SELECT * FROM journal_lines ORDER BY id').all()).toEqual(before);
  });
  it('F-001 rejects a sales return dated before its source invoice', async () => {
    const warehouse = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    const item = await createItem('Chronology', cookie);
    await purchaseStock(item, warehouse, 10, 10, cookie);
    const customer = await createCustomer('Chronology', cookie);
    const invoice = await createInvoice({ customerId: customer, itemId: item, invoiceDate: '2026-09-11', lines: [{ quantity: 2, unitPrice: 15 }] }, cookie);
    const before = db.prepare('SELECT * FROM journal_lines ORDER BY id').all();
    const ret = await processReturn(invoice.invoiceId, { invoiceItemIds: invoice.invoiceItemIds, quantities: [1], warehouseId: warehouse, returnDate: '2026-09-10' }, cookie);
    expect(ret.status).toBe(400);
    expect(db.prepare('SELECT * FROM journal_lines ORDER BY id').all()).toEqual(before);
  });
  it('F-001 rejects a purchase return dated before its source purchase', async () => {
    const warehouse = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    const item = await createItem('Purchase chronology', cookie);
    await purchaseStock(item, warehouse, 10, 10, cookie, '2026-09-10');
    const source = db.prepare('SELECT id FROM purchases WHERE item_id=?').get(item) as { id: number };
    const before = db.prepare('SELECT * FROM journal_lines ORDER BY id').all();
    const ret = await post('/api/purchase-returns', { source_type: 'PURCHASE', source_id: source.id, return_date: '2026-09-09', warehouse_id: warehouse, disposition: 'credit_on_account', items: [{ source_item_id: source.id, quantity: 1 }] });
    expect(ret.status).toBe(400);
    expect(db.prepare('SELECT * FROM journal_lines ORDER BY id').all()).toEqual(before);
  });
  it('F-023 settles closed July liabilities in October without rewriting July', async () => {
    const supplier = await post('/api/suppliers', { supplier_code: 'D15', supplier_name: 'D15 Supplier' });
    expect(supplier.status).toBe(201);
    const category = db.prepare('SELECT category_name FROM expense_categories LIMIT 1').get() as { category_name: string };
    const expense = await post('/api/expenses', { expense_category: category.category_name, amount: 100, expense_date: '2026-07-10', payment_method: 'Credit', description: 'D15' });
    expect(expense.status).toBe(201);
    expect((await request(app).put(`/api/expenses/${expense.body.data.id}`).set('Cookie', cookie).send({ status: 'Recorded' })).status).toBe(200);
    const bill = await post('/api/supplier-bills', { supplier_id: supplier.body.id ?? supplier.body.data.id, bill_no: 'D15', bill_date: '2026-07-10', description: 'D15', net_amount: 100, input_tax_amount: 0 });
    expect(bill.status).toBe(201);
    const period = db.prepare("SELECT id FROM accounting_periods WHERE period_name='2026-07'").get() as { id: number };
    expect((await post(`/api/accounting/periods/${period.id}/close`, {})).status).toBe(200);
    const july = db.prepare("SELECT * FROM journal_lines WHERE line_date<='2026-07-31' ORDER BY id").all();
    const bank = net('1010');
    for (const url of [`/api/expenses/${expense.body.data.id}/payments`, `/api/supplier-bills/${bill.body.data.id}/payments`]) {
      const body = { amount: 100, payment_date: '2026-10-01', payment_method: 'Bank' };
      const paid = await request(app).post(url).set('Cookie', cookie).set('Idempotency-Key', `D15-${url}`).send(body);
      expect(paid.status).toBe(201);
      expect((await request(app).post(url).set('Cookie', cookie).set('Idempotency-Key', `D15-${url}`).send(body)).status).toBe(201);
    }
    expect(net('1010') - bank).toBe(-20000);
    expect(net('2115')).toBe(0);
    expect(db.prepare("SELECT * FROM journal_lines WHERE line_date<='2026-07-31' ORDER BY id").all()).toEqual(july);
  });
});
