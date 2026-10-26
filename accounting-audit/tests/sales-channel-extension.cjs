'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {createRequire} = require('node:module');
const root = path.resolve(__dirname, '../..');
const fromServer = createRequire(path.join(root, 'server/package.json'));
const run = fs.mkdtempSync(path.join(root, 'accounting-audit/evidence/sales-channel-run-'));
process.env.NODE_ENV = 'test';
process.env.DATABASE_PATH = run;
process.env.JWT_SECRET = 'sales-channel-isolated-fixture-secret-2026';
process.env.DEFAULT_ADMIN_PASSWORD = 'Sales-channel-fixture-password-2026!';
process.env.LOG_DIR = path.join(run, 'logs');
const sqlitePath = fromServer.resolve('better-sqlite3');
const NativeDatabase = fromServer(sqlitePath);
const openedDatabases = [];
fromServer.cache[sqlitePath].exports = new Proxy(NativeDatabase, {construct(Target, args) {
  assert.equal(typeof args[0], 'string');
  const file = path.resolve(args[0]);
  assert(file.startsWith(run + path.sep), 'Refusing SQLite outside fresh fixture: ' + file);
  openedDatabases.push(file);
  return Reflect.construct(Target, args);
}});
fromServer('ts-node').register({transpileOnly:true, project:path.join(root,'server/tsconfig.json')});
const config = fromServer('./src/config/database');
const db = config.default;
fromServer.cache[fromServer.resolve('@jest/globals')] = {exports:{expect:fromServer('expect').expect}};
const invariants = fromServer('./src/__tests__/helpers/accountingInvariants');
const request = fromServer('supertest');
const events = [], checks = [], scenarios = [], snapshots = [], fixtureWrites = [];
let app, cookie, serial = 0;
const today = new Date().toISOString().slice(0,10);
const write = (name, data) => fs.writeFileSync(path.join(run,name), JSON.stringify(data,null,2));
function check(label, actual, expected) {
  const pass = JSON.stringify(actual) === JSON.stringify(expected);
  checks.push({label,actual,expected,pass});
  if (!pass) console.log('MISMATCH', label, JSON.stringify({actual,expected}));
}
const tables = ['quotations','quotation_items','sales_orders','sales_order_items','invoices','invoice_items','invoice_returns','invoice_return_items','return_settlements','payments','payment_allocations','customers','customer_ledger','suppliers','supplier_ledger','purchases','stock_balances','stock_batches','stock_movements','stock_reservations','batch_stock_by_location','journal_entries','journal_lines','accounting_periods'];
function state() {const data={};for(const table of tables)data[table]=db.prepare('SELECT * FROM '+table).all();return data;}
function hash() {return crypto.createHash('sha256').update(JSON.stringify(state())).digest('hex');}
function gl(code) {return Math.round(db.prepare('SELECT COALESCE(SUM(j.debit-j.credit),0) amount FROM journal_lines j JOIN chart_of_accounts a ON a.id=j.account_id WHERE a.code=? AND j.voided=0').get(code).amount*100);}
const codes = ['1000','1010','1100','1110','1200','2000','4000','4100','5000'];
const balances = () => Object.fromEntries(codes.map(code=>[code,gl(code)]));
function delta(label,before,expected) {for(const code of codes)check(label+' GL '+code+' paise',gl(code)-before[code],expected[code]??0);}
function snapshot(label) {
  const file = String(snapshots.length+1).padStart(2,'0')+'-'+label+'.json';
  const collected = {};
  for(const name of ['customerArImbalances','supplierApImbalances','stockImbalances','arImbalances','apImbalances','inventoryImbalances','cashImbalances','orphanSourceBatches','unappliedLiabilityImbalances','creditSourceConsumptionImbalances','creditSourceBoundsImbalances','receiptAllocationImbalances','supplierAdvanceImbalances','expensePayableImbalances','inputTaxImbalances']) {
    collected[name]=invariants[name](db);check(label+' '+name,collected[name],[]);
  }
  const grouped=invariants.glImbalances(db);check(label+' invariant A reference groups',grouped.groups,[]);check(label+' invariant A overall paise',Math.round(grouped.totalDiff*100),0);
  const unbalanced=db.prepare('SELECT journal_entry_id,ROUND(SUM(debit-credit),6) delta FROM journal_lines WHERE voided=0 GROUP BY journal_entry_id HAVING ABS(SUM(debit-credit))>0.001').all();
  check(label+' individual journal groups balanced',unbalanced,[]);
  const signed=Math.round(db.prepare('SELECT COALESCE(SUM(current_balance-credit_balance),0) amount FROM customers').get().amount*100);
  check(label+' signed AR',gl('1100')+gl('1110'),signed);
  write(file,{label,balances:balances(),state:state(),invariants:collected,referenceGroups:grouped,individualJournalGroups:unbalanced,signedArPaise:signed});snapshots.push(file);return file;
}
async function api(method,url,body,headers={}) {
  const before=hash();let req=request(app)[method](url).set('Cookie',cookie);
  for(const [name,value] of Object.entries(headers))req=req.set(name,value);
  if(body!==undefined)req=req.send(body);
  const res=await req;const after=hash();
  events.push({method,url,body,headers,status:res.status,response:res.body,replayed:res.headers['x-idempotent-replay'],before,after});write('api-events.json',events);
  if(res.status>=400)check('rejection atomic '+method+' '+url,after,before);
  return res;
}
async function ok(method,url,body,headers) {const res=await api(method,url,body,headers);assert(res.status>=200&&res.status<300,method+' '+url+' '+res.status+' '+JSON.stringify(res.body));return res.body.data??res.body;}
async function scenario(id,fn) {const start=checks.length,startEvent=events.length,startSnapshot=snapshots.length;try{await fn();scenarios.push({id,status:checks.slice(start).every(c=>c.pass)?'PASS':'FAIL',checks:[start,checks.length],events:[startEvent,events.length],artifacts:snapshots.slice(startSnapshot)});}catch(error){scenarios.push({id,status:'BLOCKED',error:String(error),checks:[start,checks.length],events:[startEvent,events.length],artifacts:snapshots.slice(startSnapshot)});}write('results.json',{run,scenarios,checks});}
async function fixture(label,quantity=40) {
  const item=await ok('post','/api/inventory/items',{item_code:'SC-'+(++serial),item_name:label,unit_of_measure:'pcs'});
  const customer=await ok('post','/api/customers',{customer_code:'SC-C-'+serial,customer_name:label,phone:'03000000000'});
  const supplier=await ok('post','/api/suppliers',{supplier_code:'SC-S-'+serial,supplier_name:label});
  const warehouse=db.prepare("SELECT id FROM warehouses WHERE is_active=1 AND warehouse_code NOT IN ('EXPIRED','DAMAGED') ORDER BY id LIMIT 1").get().id;
  await ok('post','/api/purchases',{item_id:item.id,supplier_id:supplier.id,warehouse_id:warehouse,quantity,unit_cost:9.25,purchase_date:'2026-09-01'});
  return {item:item.id,customer:customer.id,warehouse};
}
function seedLocation(batch,location,quantity) {
  const sql='INSERT INTO batch_stock_by_location (batch_id,location_id,quantity_physical,quantity_reserved,quantity_available) VALUES (?,?,?,0,?)';
  db.prepare(sql).run(batch,location,quantity,quantity);
  fixtureWrites.push({sql,params:[batch,location,quantity,quantity],purpose:'Fresh feature-enabled fixture: mirror purchased batch quantity at its default location before reservation operations'});
}
const qty=f=>db.prepare('SELECT SUM(quantity_remaining) amount FROM stock_batches WHERE item_id=?').get(f.item).amount;
const items=(f,n)=>[{item_id:f.item,quantity:n,unit_price:17.35}];
async function returnUnits(invoiceId,n,settlements) {
  const line=db.prepare('SELECT id FROM invoice_items WHERE invoice_id=?').get(invoiceId).id;
  return ok('post',`/api/invoices/${invoiceId}/return`,{return_date:today,items:[{invoice_item_id:line,return_quantity:n}],...(settlements?{settlements}:{})},{'Idempotency-Key':'SC-return-'+invoiceId});
}
(async()=>{
  config.applyPendingMigrations();await config.dbSeedReady;
  app=fromServer('./src/app').default;
  const login=await request(app).post('/api/auth/login').send({username:'admin',password:process.env.DEFAULT_ADMIN_PASSWORD});assert.equal(login.status,200);
  cookie=login.headers['set-cookie'].find(c=>c.startsWith('token=')).split(';')[0];
  write('auth.json',{route:'/api/auth/login',status:login.status,authenticatedCookiePresent:Boolean(cookie),credentials:'isolated fixture only; omitted'});
  write('schema.json',db.prepare("SELECT name,sql FROM sqlite_master WHERE type IN ('table','trigger')").all());
  await ok('post','/api/owner-equity/capital',{capital_date:'2026-09-01',amount:10000});
  await scenario('quotation-confirmed-order-invoice-cancel',async()=>{
    const f=await fixture('Quotation lifecycle');const base=balances();snapshot('quotation-before');
    const quote=await ok('post','/api/quotations',{customer_id:f.customer,quotation_date:today,warehouse_id:f.warehouse,items:items(f,3)});
    check('quotation total exact paise',Math.round(quote.total_amount*100),5205);
    await ok('put',`/api/quotations/${quote.id}`,{status:'Sent'});await ok('put',`/api/quotations/${quote.id}`,{status:'Accepted'});
    const converted=await ok('post',`/api/quotations/${quote.id}/convert`,{});const order=await ok('get',`/api/sales-orders/${converted.salesOrderId}`);
    check('converted order confirmed',order.status,'Confirmed');check('pre-invoice stock',qty(f),40);delta('quotation and confirmed order',base,{});snapshot('quotation-converted-no-financial-effect');
    const twice=await api('post',`/api/quotations/${quote.id}/convert`,{});check('quotation repeat conversion 400',twice.status,400);
    const inv=await ok('post',`/api/sales-orders/${order.id}/convert`,{invoice_date:today});
    delta('SO invoice',base,{'1200':-2775,'1100':5205,'4000':-5205,'5000':2775});check('SO stock after invoice',qty(f),37);
    check('SO line delivered',db.prepare('SELECT delivered_quantity FROM sales_order_items WHERE so_id=?').get(order.id).delivered_quantity,3);snapshot('sales-order-invoiced');
    await ok('post',`/api/sales-orders/${order.id}/cancel`,{});delta('SO cancel neutrality',base,{});check('SO cancel stock',qty(f),40);check('linked invoice cancelled',db.prepare('SELECT status FROM invoices WHERE id=?').get(inv.invoiceId).status,'Cancelled');snapshot('sales-order-cancelled');
    const repeated=await api('post',`/api/sales-orders/${order.id}/cancel`,{});check('F070 repeated SO cancellation is 4xx',repeated.status>=400&&repeated.status<500,true);snapshot('sales-order-repeat-cancel');
  });
  await scenario('direct-order-confirm-deliver-paid-guard',async()=>{
    const f=await fixture('Direct order');const base=balances();snapshot('direct-order-before');
    const order=await ok('post','/api/sales-orders',{customer_id:f.customer,so_date:today,warehouse_id:f.warehouse,items:items(f,2)});
    await ok('put',`/api/sales-orders/${order.id}`,{status:'Confirmed'});await ok('put',`/api/sales-orders/${order.id}`,{status:'Delivered'});delta('delivered status before invoice',base,{});check('delivered status physical stock',qty(f),40);snapshot('direct-order-delivered');
    const inv=await ok('post',`/api/sales-orders/${order.id}/convert`,{invoice_date:today});
    const pay=await ok('post','/api/payments',{customer_id:f.customer,payment_date:today,amount:34.70,payment_method:'cash',invoice_allocations:[{invoice_id:inv.invoiceId,amount:34.70}]});
    delta('paid SO',base,{'1000':3470,'1200':-1850,'4000':-3470,'5000':1850});snapshot('direct-order-paid');
    const rejected=await api('post',`/api/sales-orders/${order.id}/cancel`,{});check('paid SO cancellation protected',rejected.status,409);
    await ok('delete',`/api/payments/${pay.id}`);await ok('post',`/api/sales-orders/${order.id}/cancel`,{});delta('paid SO reverse neutrality',base,{});check('paid SO stock restore',qty(f),40);snapshot('direct-order-reversed');
  });
  await scenario('pos-cash-walkin-replay-partial-return',async()=>{
    const f=await fixture('POS walkin');const base=balances();snapshot('pos-cash-before');
    const body={warehouse_id:f.warehouse,sale_date:today,items:items(f,4),cash_received:100};const headers={'Idempotency-Key':'SC-walkin-cash'};
    const sale=await ok('post','/api/pos/sale',body,headers);check('POS cash change paise',Math.round(sale.change*100),3060);delta('POS cash',base,{'1000':6940,'1200':-3700,'4000':-6940,'5000':3700});check('POS cash quantity',qty(f),36);snapshot('pos-cash-sale');
    const before=hash();const replay=await api('post','/api/pos/sale',body,headers);check('POS replay status',replay.status,201);check('POS replay header',replay.headers['x-idempotent-replay'],'true');check('POS replay body',replay.body.data,sale);check('POS replay economic state',hash(),before);
    const conflict=await api('post','/api/pos/sale',{...body,cash_received:101},headers);check('POS changed replay rejected',conflict.status,409);snapshot('pos-cash-replay');
    await returnUnits(sale.sale_ids[0],1,[{type:'refund',amount:17.35,method:'Cash'}]);
    delta('POS cash partial return',base,{'1000':5205,'1200':-2775,'4000':-6940,'4100':1735,'5000':2775});check('POS cash return quantity',qty(f),37);snapshot('pos-cash-return');
  });
  await scenario('pos-named-credit-partial-return',async()=>{
    const f=await fixture('POS credit');const base=balances();snapshot('pos-credit-before');
    const body={customer_id:f.customer,warehouse_id:f.warehouse,sale_date:today,items:items(f,5),payments:[]};const headers={'Idempotency-Key':'SC-credit'};
    const sale=await ok('post','/api/pos/sale',body,headers);delta('POS credit',base,{'1100':8675,'1200':-4625,'4000':-8675,'5000':4625});check('POS credit quantity',qty(f),35);snapshot('pos-credit-sale');
    const before=hash();await ok('post','/api/pos/sale',body,headers);check('POS credit replay no writes',hash(),before);
    await returnUnits(sale.sale_ids[0],2);delta('POS unpaid partial return',base,{'1100':5205,'1200':-2775,'4000':-8675,'4100':3470,'5000':2775});check('POS unpaid return quantity',qty(f),37);snapshot('pos-credit-return');
  });
  await scenario('pos-split-cash-bank-credit',async()=>{
    const f=await fixture('POS split');const base=balances();snapshot('pos-split-before');
    await ok('post','/api/pos/sale',{customer_id:f.customer,warehouse_id:f.warehouse,sale_date:today,items:items(f,3),payments:[{amount:20,payment_method:'Cash'},{amount:15,payment_method:'Bank'}]},{'Idempotency-Key':'SC-split'});
    delta('POS split',base,{'1000':2000,'1010':1500,'1100':1705,'1200':-2775,'4000':-5205,'5000':2775});check('POS split quantity',qty(f),37);snapshot('pos-split-sale');
  });
  await scenario('pos-explicit-zero-cash',async()=>{
    const f=await fixture('POS zero tender');const before=hash();snapshot('pos-zero-before');
    const res=await api('post','/api/pos/sale',{warehouse_id:f.warehouse,sale_date:today,items:items(f,1),cash_received:0},{'Idempotency-Key':'SC-zero-cash-valid'});
    check('F073 explicit zero cash rejected',res.status>=400&&res.status<500,true);check('F073 zero tender no financial mutation',hash(),before);snapshot('pos-zero-after');
  });
  await scenario('reservation-line-replay-release',async()=>{
    db.prepare("UPDATE settings SET value='1' WHERE key='feature_batch_locations'").run();fixtureWrites.push({sql:"UPDATE settings SET value='1' WHERE key='feature_batch_locations'",purpose:'Enable optional batch-location feature in fresh disposable fixture only'});
    const f=await fixture('Reservation replay',10);const base=balances();const batch=db.prepare('SELECT id FROM stock_batches WHERE item_id=?').get(f.item).id;const location=db.prepare("SELECT id FROM locations WHERE warehouse_id=? AND location_code='DEFAULT'").get(f.warehouse).id;
    seedLocation(batch,location,10);
    const body={item_id:f.item,warehouse_id:f.warehouse,batch_id:batch,location_id:location,quantity_reserved:3,reference_doctype:'SALES_ORDER',reference_docno:'SC-RES-REPLAY',reference_line_id:1};
    snapshot('reservation-before');const first=await ok('post','/api/inventory/reservations',body);const replay=await ok('post','/api/inventory/reservations',body);
    check('reservation replay same record',replay.id,first.id);check('F071 reservation replay reserves once',db.prepare('SELECT quantity_reserved FROM batch_stock_by_location WHERE batch_id=? AND location_id=?').get(batch,location).quantity_reserved,3);snapshot('reservation-replayed');
    await ok('delete',`/api/inventory/reservations/${first.id}/release`);check('F071 release restores all availability',db.prepare('SELECT quantity_available FROM batch_stock_by_location WHERE batch_id=? AND location_id=?').get(batch,location).quantity_available,10);delta('reservation no GL',base,{});check('reservation physical unchanged',qty(f),10);snapshot('reservation-released');
  });
  await scenario('reservation-single-line-release-control',async()=>{
    const f=await fixture('Reservation single control',10);const base=balances();const batch=db.prepare('SELECT id FROM stock_batches WHERE item_id=?').get(f.item).id;const location=db.prepare("SELECT id FROM locations WHERE warehouse_id=? AND location_code='DEFAULT'").get(f.warehouse).id;
    seedLocation(batch,location,10);snapshot('reservation-control-before');
    const r=await ok('post','/api/inventory/reservations',{item_id:f.item,warehouse_id:f.warehouse,batch_id:batch,location_id:location,quantity_reserved:3,reference_doctype:'SALES_ORDER',reference_docno:'SC-RES-CONTROL',reference_line_id:2});
    check('single reservation available quantity',db.prepare('SELECT quantity_available FROM batch_stock_by_location WHERE batch_id=? AND location_id=?').get(batch,location).quantity_available,7);snapshot('reservation-control-active');
    await ok('delete',`/api/inventory/reservations/${r.id}/release`);check('single release restores availability',db.prepare('SELECT quantity_available FROM batch_stock_by_location WHERE batch_id=? AND location_id=?').get(batch,location).quantity_available,10);
    const repeat=await api('delete',`/api/inventory/reservations/${r.id}/release`);check('single release repeat rejected',repeat.status,400);delta('single reservation GL neutral',base,{});snapshot('reservation-control-released');
  });
  await scenario('reservation-without-optional-line-release',async()=>{
    const f=await fixture('Reservation no line',10);const batch=db.prepare('SELECT id FROM stock_batches WHERE item_id=?').get(f.item).id;const location=db.prepare("SELECT id FROM locations WHERE warehouse_id=? AND location_code='DEFAULT'").get(f.warehouse).id;
    seedLocation(batch,location,10);
    snapshot('reservation-noline-before');const r=await ok('post','/api/inventory/reservations',{item_id:f.item,warehouse_id:f.warehouse,batch_id:batch,location_id:location,quantity_reserved:2,reference_doctype:'SALES_ORDER',reference_docno:'SC-RES-NOLINE'});
    const released=await api('delete',`/api/inventory/reservations/${r.id}/release`);check('F072 release optional-line reservation succeeds',released.status,200);check('F072 reservation no longer active',db.prepare('SELECT status FROM stock_reservations WHERE id=?').get(r.id).status,'RELEASED');snapshot('reservation-noline-after');
  });
  check('SQLite integrity',db.pragma('integrity_check'),[{integrity_check:'ok'}]);check('SQLite foreign keys',db.pragma('foreign_key_check'),[]);
})().catch(error=>{scenarios.push({id:'harness',status:'BLOCKED',error:String(error),stack:error.stack});process.exitCode=2;}).finally(()=>{
  const result={run,today,invocation:'node accounting-audit/tests/sales-channel-extension.cjs',guard:{nodeEnv:process.env.NODE_ENV,databasePath:process.env.DATABASE_PATH,openedDatabases},fixtureWrites,scenarios,checks,summary:{total:checks.length,pass:checks.filter(c=>c.pass).length,fail:checks.filter(c=>!c.pass).length},snapshots};
  write('results.json',result);fs.writeFileSync(path.join(root,'accounting-audit/evidence/sales-channel-latest-run.txt'),run+'\n');
  if(checks.some(c=>!c.pass)||scenarios.some(s=>s.status==='BLOCKED'))process.exitCode=1;
  db.close();fromServer('./src/middleware/rateLimiter').shutdownRateLimiters();fromServer('./src/utils/logger').default.close();
  console.log(JSON.stringify({run,scenarios,summary:result.summary},null,2));
});
