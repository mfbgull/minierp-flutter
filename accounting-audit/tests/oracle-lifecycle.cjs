'use strict';
const fs = require('node:fs');
const path = require('node:path');
const {createRequire} = require('node:module');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '../..');
const fromServer = createRequire(path.join(root, 'server/package.json'));
const evidenceRoot = path.join(root, 'accounting-audit/evidence');
const runDir = fs.mkdtempSync(path.join(evidenceRoot, 'oracle-run-'));
process.env.NODE_ENV = 'test';
process.env.DATABASE_PATH = runDir;
process.env.JWT_SECRET = 'audit-only-isolated-jwt-secret-2026-10';
process.env.DEFAULT_ADMIN_PASSWORD = 'AuditOnly!Isolated2026';
const NativeDB = fromServer('better-sqlite3');
fromServer.cache[fromServer.resolve('better-sqlite3')].exports = new Proxy(NativeDB, {
  construct(Target,args) {
    if (typeof args[0] !== 'string' || !path.resolve(args[0]).startsWith(runDir + path.sep)) throw new Error('AUDIT DB SAFETY: outside run directory');
    return new Target(...args);
  }
});
fromServer('ts-node').register({transpileOnly:true,project:path.join(root,'server/tsconfig.json')});
const config = fromServer('./src/config/database');
const db = config.default;
const request = fromServer('supertest');
const app = fromServer('./src/app').default;
// The collectors are production SQL readers; only their test assertion import needs a standalone adapter.
fromServer.cache[fromServer.resolve('@jest/globals')] = { exports: { expect: fromServer('expect').expect } };
const invariants = fromServer('./src/__tests__/helpers/accountingInvariants');
const events = [], checks = [], families = [];
let cookie = '', serial = 0;
const write = (name,data) => fs.writeFileSync(path.join(runDir,name), JSON.stringify(data,null,2));
function check(label, actual, expected) { const pass=JSON.stringify(actual)===JSON.stringify(expected); checks.push({label,actual,expected,pass}); if(!pass) console.log('MISMATCH',label,actual,'expected',expected); }
function paise(value) { const s=String(value); if(!/^-?\d+(\.\d{1,2})?$/.test(s)) throw new Error('Oracle input requires exact cents: '+s); const neg=s.startsWith('-'); const [whole,frac='']=s.replace('-','').split('.'); return (neg?-1n:1n)*(BigInt(whole)*100n+BigInt(frac.padEnd(2,'0'))); }
function gl(code) {return Math.round(db.prepare('SELECT COALESCE(SUM(j.debit-j.credit),0) n FROM journal_lines j JOIN chart_of_accounts a ON a.id=j.account_id WHERE j.voided=0 AND a.code=?').get(code).n*100);}
function economicHash() {
 const rows={};for(const table of ['invoices','invoice_items','invoice_returns','return_settlements','payments','payment_allocations','customers','customer_ledger','suppliers','supplier_ledger','purchases','purchase_returns','stock_batches','stock_balances','journal_lines']) rows[table]=db.prepare('SELECT * FROM '+table).all();
 return crypto.createHash('sha256').update(JSON.stringify(rows)).digest('hex');
}
function snapshot(label) {
 const data={label,accounts:db.prepare('SELECT a.code,ROUND(SUM(j.debit-j.credit),8) balance FROM journal_lines j JOIN chart_of_accounts a ON a.id=j.account_id WHERE j.voided=0 GROUP BY a.code').all()};
 for(const table of ['invoices','invoice_items','invoice_returns','invoice_return_items','return_settlements','payments','payment_allocations','customers','customer_ledger','suppliers','supplier_ledger','purchases','purchase_returns','purchase_return_items','purchase_order_items','goods_receipts','stock_batches','stock_balances','journal_lines','accounting_periods']) data[table]=db.prepare('SELECT * FROM '+table).all();
 write(String(events.length).padStart(3,'0')+'-'+label+'.json',data);
 const unbalanced=db.prepare('SELECT journal_entry_id,ROUND(SUM(debit-credit),6) delta FROM journal_lines WHERE voided=0 GROUP BY journal_entry_id HAVING ABS(SUM(debit-credit))>0.001').all();
 check(label+' balanced journal groups',unbalanced,[]);
 const collectors = ['customerArImbalances','supplierApImbalances','stockImbalances','arImbalances','apImbalances','inventoryImbalances','cashImbalances','orphanSourceBatches','unappliedLiabilityImbalances','creditSourceConsumptionImbalances','creditSourceBoundsImbalances','receiptAllocationImbalances','supplierAdvanceImbalances','expensePayableImbalances','inputTaxImbalances'];
 const collected = {};
 for(const name of collectors) { collected[name]=invariants[name](db); check(label+' '+name,collected[name],[]); }
 write(String(events.length).padStart(3,'0')+'-'+label+'-invariants.json',collected);
 const signedCustomers=db.prepare('SELECT COALESCE(SUM(current_balance-credit_balance),0) n FROM customers').get().n;
 check(label+' signed AR GL vs customer net',gl('1100')+gl('1110'),Math.round(signedCustomers*100));
 return data;
}
async function api(method,url,body,headers={}) {
 const before=method==='get'?null:economicHash();
 let req=request(app)[method](url).set('Cookie',cookie); for(const [k,v] of Object.entries(headers))req=req.set(k,v); if(body!==undefined) req=req.send(body);
 const r=await req; const after=before?economicHash():null; events.push({method,url,body,status:r.status,response:r.body,economicHashBefore:before,economicHashAfter:after});write('api-events.json',events);
 if(r.status>=400&&before)check('rejected '+method+' '+url+' economic atomicity',after,before);
 return r;
}
async function ok(method,url,body,headers) {const r=await api(method,url,body,headers);if(r.status<200||r.status>=300)throw new Error(method+' '+url+' '+r.status+' '+JSON.stringify(r.body));return r.body.data??r.body;}
async function fixture(label,qty=70,cost=10,date='2026-09-01') {
 serial++;const item=await ok('post','/api/inventory/items',{item_code:'OR-'+serial,item_name:label,unit_of_measure:'pcs'});
 const supplier=await ok('post','/api/suppliers',{supplier_code:'OR-S-'+serial,supplier_name:label});
 const customer=await ok('post','/api/customers',{customer_code:'OR-C-'+serial,customer_name:label,phone:'0300-0000000'});
 const warehouse=db.prepare("SELECT id FROM warehouses WHERE warehouse_code NOT IN ('DAMAGED','EXPIRED') ORDER BY id LIMIT 1").get().id;
 const purchase=await ok('post','/api/purchases',{item_id:item.id,supplier_id:supplier.id,warehouse_id:warehouse,quantity:qty,unit_cost:cost,purchase_date:date});
 return {item:item.id,supplier:supplier.id,customer:customer.id,warehouse,purchase:purchase.id};
}
async function sale(f,qty,price=15,date='2026-09-02',extra={}) {serial++;return ok('post','/api/invoices',{invoice_no:'OR-I-'+serial,customer_id:f.customer,invoice_date:date,warehouse_id:f.warehouse,items:[{item_id:f.item,warehouse_id:f.warehouse,quantity:qty,unit_price:price}],...extra});}
async function pay(f,invoice,amount,date='2026-09-02') {return ok('post','/api/payments',{customer_id:f.customer,payment_date:date,amount,payment_method:'cash',invoice_allocations:[{invoice_id:invoice.id,amount}]});}
function itemLine(inv){return db.prepare('SELECT id FROM invoice_items WHERE invoice_id=?').get(inv.id).id;}
function qty(f){return db.prepare('SELECT COALESCE(SUM(quantity_remaining),0) q FROM stock_batches WHERE item_id=?').get(f.item).q;}
async function family(id,name,fn) {if(process.env.ORACLE_FAMILY && process.env.ORACLE_FAMILY!==String(id))return;const start=checks.length;try{await fn();families.push({id,name,status:checks.slice(start).every(c=>c.pass)?'PASS':'FAIL',checks:checks.length-start});}catch(e){families.push({id,name,status:'BLOCKED',error:String(e)});console.log('FAMILY ERROR',id,String(e));} write('results.json',{runDir,families,checks});}
(async()=>{
 config.applyPendingMigrations();await config.dbSeedReady;
 write('schema.json',db.prepare("SELECT name,sql FROM sqlite_master WHERE type='table'").all());
 const login=await request(app).post('/api/auth/login').send({username:'admin',password:process.env.DEFAULT_ADMIN_PASSWORD});
 if(login.status!==200)throw new Error('login '+login.status+' '+JSON.stringify(login.body));
 cookie=login.headers['set-cookie'].find(c=>c.startsWith('token=')).split(';')[0];
 await ok('post','/api/owner-equity/capital',{capital_date:'2026-09-01',amount:10000});
 if(process.env.ORACLE_SUPPLEMENT==='1') {
  await require('./oracle-supplement.cjs')({db,api,ok,gl,check,snapshot,family,fixture,sale,pay,itemLine,qty});
  write('results.json',{runDir,families,checks});console.log(JSON.stringify({runDir,families,failedChecks:checks.filter(c=>!c.pass)},null,2));return;
 }
 await family(1,'retail: 70 @10, sell 15 @15, three returns, resale 2, damage 1, expense10',async()=>{
  const base={inventory:gl('1200'),revenue:gl('4000'),cogs:gl('5000'),cash:gl('1000')};
  const f=await fixture('retail');const inv=await sale(f,15);await pay(f,inv,225);
  for(let n=1;n<=3;n++) {await ok('post',`/api/invoices/${inv.id}/return`,{return_date:'2026-09-03',items:[{invoice_item_id:itemLine(inv),return_quantity:1}],settlements:[{type:'refund',amount:15,method:'Cash'}]},{'Idempotency-Key':'retail-return-'+n});snapshot('retail-return-'+n);}
  await sale(f,2,15,'2026-09-04');
  check('retail quantity',qty(f),56);check('retail inventory paise',gl('1200')-base.inventory,Number(56n*paise(10)));check('retail COGS paise',gl('5000')-base.cogs,Number(14n*paise(10)));
  const damagedWarehouse=db.prepare("SELECT id FROM warehouses WHERE warehouse_code='DAMAGED'").get().id;
  await ok('post','/api/inventory/stock-transfers',{item_id:f.item,from_warehouse_id:f.warehouse,to_warehouse_id:damagedWarehouse,quantity:1,remarks:'one returned item broken'});
  const damaged=db.prepare('SELECT id FROM stock_batches WHERE item_id=? AND warehouse_id=? AND quantity_remaining=1 ORDER BY id DESC LIMIT 1').get(f.item,damagedWarehouse);
  await ok('post','/api/inventory/damaged/write-off',{batchIds:[damaged.id],reason:'one damaged return',glAccount:'7202'});
  const category=db.prepare('SELECT category_name FROM expense_categories ORDER BY id LIMIT 1').get().category_name;
  const expense=await ok('post','/api/expenses',{expense_category:category,expense_date:'2026-09-04',amount:10,payment_method:'Cash'});await ok('put',`/api/expenses/${expense.id}`,{status:'Recorded'});
  check('retail final stock quantity',qty(f),55);check('retail final inventory',gl('1200'),55000);check('retail final cash',gl('1000'),1017000);check('retail AR',gl('1100'),3000);check('retail AP',gl('2000'),-70000);check('retail gross revenue',gl('4000'),-25500);check('retail returns',gl('4100'),4500);check('retail damage expense',gl('7202'),1000);check('retail operating expense',gl('6000'),1000);
  snapshot('retail');for(const endpoint of ['profit-loss','balance-sheet','trial-balance','cash-flow','inventory-valuation','ar-aging','ap-aging']){
   const report=await ok('get','/api/reports/'+endpoint+'?fromDate=2026-09-01&toDate=2026-10-31&asOfDate=2026-10-31');
   if(endpoint==='balance-sheet'){check('retail report assets',report.totals.total_assets,10750);check('retail report equity',report.equity.total,10050);check('retail report as-of',report.asOfDate,'2026-10-31');}
   if(endpoint==='profit-loss'){check('retail report net revenue',report.totalRevenue,210);check('retail report net COGS',report.totalCogs,140);check('retail report all expenses',report.totalExpenses,20);check('retail report net profit',report.netProfit,50);}
   if(endpoint==='inventory-valuation'){check('retail report physical quantity',report.totalPhysical.qty,55);check('retail report physical value',report.totalPhysical.value,550);}
   if(endpoint==='ar-aging')check('retail report AR',report.summary.totalReceivables,30);
   if(endpoint==='ap-aging')check('retail report AP',report.summary.totalPayables,700);
  }
  await ok('get','/api/dashboard/summary?fromDate=2026-09-01&toDate=2026-10-31');
 });
 await family(2,'partial payment return, credit and settlement cap',async()=>{
  const f=await fixture('credits',20);const inv=await sale(f,10);await pay(f,inv,100);const beforeCash=gl('1000');
  const returned=await ok('post',`/api/invoices/${inv.id}/return`,{return_date:'2026-09-03',items:[{invoice_item_id:itemLine(inv),return_quantity:4}],settlements:[{type:'refund',amount:5,method:'Cash'},{type:'credit',amount:5}]});
  check('partial customer cash refund',gl('1000')-beforeCash,-500);const position=await ok('get',`/api/invoices/${inv.id}/position`);check('partial return balance',position.balanceDue,0);check('partial return settled',position.settledAmount,10);
  const before=snapshot('credit-settled');const over=await api('post',`/api/invoice-returns/${returned.returnId}/settle`,{allocations:[{type:'refund',amount:0.01,method:'Cash'}]});check('over-refund rejected',over.status>=400&&over.status<500,true);check('over-refund stock unchanged',qty(f),14);snapshot('credit-over-refund');
  const target=await sale(f,1,15,'2026-09-04',{credit_offset:5});
  const targetRow=db.prepare('SELECT credit_offset,balance_amount FROM invoices WHERE id=?').get(target.id);
  check('return credit applied to new invoice',targetRow.credit_offset,5);check('return credit leaves ten receivable',targetRow.balance_amount,10);snapshot('credit-applied');
  const liability=gl('2110'),cash=gl('1000');
  await ok('post',`/api/customers/${f.customer}/unapplied-cash`,{amount:25,operation_date:'2026-09-04',payment_method:'Cash'},{'Idempotency-Key':'oracle-receipt'});
  check('unapplied cash liability',gl('2110')-liability,-2500);check('unapplied receipt cash',gl('1000')-cash,2500);
  await ok('post','/api/unapplied-cash/apply',{customer_id:f.customer,operation_date:'2026-09-04',allocations:[{invoice_id:target.id,amount:10}]},{'Idempotency-Key':'oracle-apply'});
  await ok('post','/api/unapplied-cash/refund',{customer_id:f.customer,amount:5,operation_date:'2026-09-04',payment_method:'Cash'},{'Idempotency-Key':'oracle-refund'});
  check('unapplied cash remains ten',gl('2110')-liability,-1000);check('unapplied net cash twenty',gl('1000')-cash,2000);snapshot('unapplied-cash');
 });
 await family(3,'supplier return credit and refund',async()=>{
  const f=await fixture('supplier-return',10);const cash=gl('1000'),ap=gl('2000');
  await ok('post','/api/payments',{supplier_id:f.supplier,payment_date:'2026-09-02',amount:100,payment_method:'cash',purchase_allocations:[{purchase_id:f.purchase,amount:100}]});
  const ret=await ok('post','/api/purchase-returns',{source_type:'PURCHASE',source_id:f.purchase,warehouse_id:f.warehouse,return_date:'2026-09-03',disposition:'refund_expected',items:[{source_item_id:f.purchase,quantity:3}]});
  check('supplier returned inventory',qty(f),7);check('supplier AP movement',gl('2000')-ap,13000);snapshot('supplier-return');
  const note=db.prepare("SELECT id FROM credit_notes WHERE source_type='PURCHASE_RETURN' AND source_id=?").get(ret.id);
  await ok('post','/api/supplier-refunds',{credit_note_id:note.id,refund_date:'2026-09-04',amount:20,payment_method:'cash'});
  check('supplier cash net payment less refund',gl('1000')-cash,-8000);
  snapshot('supplier-refund');
 });
 await family(4,'purchase order partial receipt and partial payment',async()=>{
  const f=await fixture('po',1);const inventory=gl('1200'),ap=gl('2000');
  const po=await ok('post','/api/purchase-orders',{supplier_id:f.supplier,warehouse_id:f.warehouse,po_date:'2026-09-02',items:[{item_id:f.item,quantity:10,unit_price:10}]});
  await ok('post',`/api/purchase-orders/${po.id}/status`,{status:'Submitted'});check('PO no inventory before receipt',gl('1200'),inventory);
  const line=db.prepare('SELECT id FROM purchase_order_items WHERE po_id=?').get(po.id).id;
  await ok('post',`/api/purchase-orders/${po.id}/receipts`,{receipt_date:'2026-09-03',warehouse_id:f.warehouse,items:[{po_item_id:line,received_quantity:4}]});
  check('partial receipt inventory',gl('1200')-inventory,4000);check('partial receipt AP',gl('2000')-ap,-4000);
  await ok('post','/api/payments',{supplier_id:f.supplier,payment_date:'2026-09-03',amount:25,payment_method:'cash',po_allocations:[{po_id:po.id,amount:25}]});check('partial receipt remaining AP',gl('2000')-ap,-1500);snapshot('po-partial');
 });
 await family(5,'damaged warehouse transfer and write-off',async()=>{
  const f=await fixture('damage',2);const inventory=gl('1200'),loss=gl('7202');const batch=db.prepare('SELECT id FROM stock_batches WHERE item_id=?').get(f.item).id;
  const transfer=await ok('post','/api/inventory/damaged/transfer',{batchId:batch,remarks:'audit damage'});check('damage transfer no loss',gl('1200'),inventory);
  await ok('post','/api/inventory/damaged/write-off',{batchIds:[transfer.mirrorBatchId],reason:'audit broken',glAccount:'7202'});check('damage quantity',qty(f),0);check('damage inventory',gl('1200')-inventory,-2000);check('damage loss',gl('7202')-loss,2000);snapshot('damage');
  const category=db.prepare('SELECT category_name FROM expense_categories ORDER BY id LIMIT 1').get().category_name;
  const expense=await ok('post','/api/expenses',{expense_category:category,expense_date:'2026-09-04',amount:7,payment_method:'Cash'});
  const cash=gl('1000'),operating=gl('6000');await ok('put',`/api/expenses/${expense.id}`,{status:'Recorded'});
  check('ordinary expense cash',gl('1000')-cash,-700);check('ordinary operating expense',gl('6000')-operating,700);snapshot('expense');
 });
 await family(6,'payment then invoice reversal, double request',async()=>{
  const f=await fixture('reverse',10);const inv=await sale(f,3);const payment=await pay(f,inv,45);await ok('delete',`/api/payments/${payment.id}`);await ok('put',`/api/invoices/${inv.id}/cancel`,{reason:'audit'});check('reversal restored quantity',qty(f),10);
  const r=await api('put',`/api/invoices/${inv.id}/cancel`,{reason:'audit duplicate'});check('duplicate cancel 4xx',r.status>=400&&r.status<500,true);check('duplicate cancel quantity',qty(f),10);snapshot('reversals');
 });
 await family(7,'backdated sale before inventory acquisition',async()=>{
  const f=await fixture('backdate',10,10,'2026-09-10');const before=qty(f);const r=await api('post','/api/invoices',{customer_id:f.customer,invoice_date:'2026-09-09',warehouse_id:f.warehouse,items:[{item_id:f.item,warehouse_id:f.warehouse,quantity:1,unit_price:15}]});check('sale before receipt rejected',r.status>=400&&r.status<500,true);check('sale before receipt quantity unchanged',qty(f),before);snapshot('backdate');
  const inv=await sale(f,1,15,'2026-09-11');const quantityBefore=qty(f);
  const historicalBefore=await ok('get','/api/reports/balance-sheet?asOfDate=2026-09-09');
  const earlyReturn=await api('post',`/api/invoices/${inv.id}/return`,{return_date:'2026-09-09',items:[{invoice_item_id:itemLine(inv),return_quantity:1}]});
  check('return before original invoice rejected',earlyReturn.status>=400&&earlyReturn.status<500,true);check('early return stock unchanged',qty(f),quantityBefore);snapshot('early-return');
  const historicalAfter=await ok('get','/api/reports/balance-sheet?asOfDate=2026-09-09');
  check('early return must not change historical inventory',historicalAfter.assets.inventory-historicalBefore.assets.inventory,0);
  const earlyProfit=await ok('get','/api/reports/profit-loss?fromDate=2026-09-09&toDate=2026-09-09');check('no revenue before source sale',earlyProfit.totalRevenue,0);check('no COGS before source sale',earlyProfit.totalCogs,0);
 });
 await family(8,'idempotency replay and changed payload',async()=>{
  const f=await fixture('retry',10);const body={customer_id:f.customer,invoice_date:'2026-09-02',warehouse_id:f.warehouse,items:[{item_id:f.item,warehouse_id:f.warehouse,quantity:2,unit_price:15}]};const headers={'Idempotency-Key':'oracle-same-invoice'};
  const a=await api('post','/api/invoices',body,headers),b=await api('post','/api/invoices',body,headers);check('invoice replay quantity',qty(f),8);check('invoice replay status',b.status<300,true);
  const c=await api('post','/api/invoices',{...body,notes:'changed'},headers);check('idempotency payload conflict',c.status,409);snapshot('duplicates');
  db.exec("CREATE TEMP TRIGGER oracle_fail_gl BEFORE INSERT ON journal_lines BEGIN SELECT RAISE(ABORT,'oracle intentional GL failure'); END");
  try {const failure=await api('post','/api/invoices',body,{'Idempotency-Key':'oracle-failed-write'});check('forced GL failure not success',failure.status>=400,true);} finally {db.exec('DROP TRIGGER oracle_fail_gl');}
  check('failed GL write stock unchanged',qty(f),8);snapshot('atomicity');
 });
 await family(9,'closed accounting period rejects posting',async()=>{
  const period=await ok('post','/api/accounting/periods',{period_name:'Audit 2025',start_date:'2025-01-01',end_date:'2025-01-31'});await ok('post',`/api/accounting/periods/${period.id}/close`,{});
  const cash=gl('1000');const r=await api('post','/api/owner-equity/capital',{capital_date:'2025-01-15',amount:10});check('closed period capital rejected',r.status>=400&&r.status<500,true);check('closed period cash unchanged',gl('1000'),cash);snapshot('period');
 });
 await family(10,'zero negative and fractional quantities',async()=>{
  const f=await fixture('bounds',10,0.1);for(const amount of [0,-1]) {const before=qty(f);const r=await api('post','/api/invoices',{customer_id:f.customer,invoice_date:'2026-09-02',warehouse_id:f.warehouse,items:[{item_id:f.item,warehouse_id:f.warehouse,quantity:amount,unit_price:1}]});check('invalid quantity '+amount,r.status>=400&&r.status<500,true);check('invalid quantity stock '+amount,qty(f),before);}
  const inv=await sale(f,3,0.1);check('decimal total exact paise',Math.round(inv.total_amount*100),30);snapshot('boundaries');
 });
 write('results.json',{runDir,families,checks});console.log(JSON.stringify({runDir,families,failedChecks:checks.filter(c=>!c.pass)},null,2));
})().catch(e=>{write('fatal.json',{error:String(e),stack:e.stack});console.error(e);process.exitCode=1;}).finally(()=>{try{fromServer('./src/services/activityLogger').disposeLogger();db.pragma('wal_checkpoint(TRUNCATE)');db.close();fromServer('./src/middleware/rateLimiter').shutdownRateLimiters();fromServer('./src/utils/logger').default.close();}finally{fs.writeFileSync(path.join(evidenceRoot,'oracle-latest.txt'),runDir+'\n');}});
