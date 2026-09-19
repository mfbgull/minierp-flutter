import request from 'supertest';
import app from './src/app';

(async () => {
  const login = await request(app).post('/api/auth/login')
    .send({ username: 'admin', password: 'test-admin-password-secure-2026' });
  const cookies = login.headers['set-cookie'];
  const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies]).find((c: string) => c.startsWith('token='));
  const authCookie = tokenCookie!.split(';')[0];

  const db = (await import('./src/config/database')).default;
  const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as any;
  const item = await request(app).post('/api/inventory/items')
    .set('Cookie', authCookie)
    .send({ item_code: 'DBG-' + Date.now(), item_name: 'dbg' });
  console.log('item', item.status);
  const itemId = item.body.id;
  const pur = await request(app).post('/api/purchases')
    .set('Cookie', authCookie)
    .send({ item_id: itemId, warehouse_id: wh.id, quantity: 10, unit_cost: 20, purchase_date: '2026-08-01', supplier_name: 'dbg' });
  console.log('purchase', pur.status, JSON.stringify(pur.body).slice(0, 150));
  const cust = await request(app).post('/api/customers')
    .set('Cookie', authCookie)
    .send({ customer_name: 'dbg cust', phone: '555' });
  const customerId = cust.body.data?.id ?? cust.body.id;
  console.log('cust', cust.status, customerId);
  const inv = await request(app).post('/api/invoices')
    .set('Cookie', authCookie)
    .send({
      invoice_no: 'INV-DBG-' + Date.now(), customer_id: customerId, invoice_date: '2026-08-10',
      due_date: '2026-08-20', status: 'Unpaid', total_amount: 100,
      items: [{ item_id: itemId, quantity: 1, unit_price: 100, warehouse_id: wh.id }],
    });
  console.log('invoice', inv.status, JSON.stringify(inv.body).slice(0, 200));
  const invoiceId = inv.body.id;

  const put = await request(app).put('/api/invoices/' + invoiceId)
    .set('Cookie', authCookie)
    .send({ record_payment: true, payment: { amount: 40, payment_date: '2026-08-11', payment_method: 'Cash' } });
  console.log('PUT record_payment:', put.status, JSON.stringify(put.body).slice(0, 300));

  // Now try the full update shape the controller expects
  const put2 = await request(app).put('/api/invoices/' + invoiceId)
    .set('Cookie', authCookie)
    .send({
      customer_id: customerId, invoice_date: '2026-08-10', due_date: '2026-08-20',
      total_amount: 100,
      items: [{ item_id: itemId, quantity: 1, unit_price: 100, warehouse_id: wh.id }],
      record_payment: true,
      payment: { amount: 40, payment_date: '2026-08-11', payment_method: 'Cash' },
    });
  console.log('PUT full:', put2.status, JSON.stringify(put2.body).slice(0, 300));
})();
