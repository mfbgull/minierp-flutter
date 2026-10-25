'use strict';
module.exports=async({db,api,ok,gl,check,snapshot,family,fixture,sale,pay,itemLine,qty})=>{
 await family('3c','supplier return credit split across two unpaid purchases',async()=>{
  const f=await fixture('supplier-credit-split',10);
  await ok('post','/api/payments',{supplier_id:f.supplier,payment_date:'2026-09-02',amount:100,payment_method:'cash',purchase_allocations:[{purchase_id:f.purchase,amount:100}]});
  const ret=await ok('post','/api/purchase-returns',{source_type:'PURCHASE',source_id:f.purchase,warehouse_id:f.warehouse,return_date:'2026-09-03',disposition:'credit_on_account',items:[{source_item_id:f.purchase,quantity:6}]});
  const note=db.prepare("SELECT id FROM credit_notes WHERE source_type='PURCHASE_RETURN' AND source_id=?").get(ret.id);
  const targets=[];for(const cost of [30,45])targets.push(await ok('post','/api/purchases',{item_id:f.item,supplier_id:f.supplier,warehouse_id:f.warehouse,quantity:1,unit_cost:cost,purchase_date:'2026-09-04'}));
  check('supplier net AP after credit and two invoices',db.prepare('SELECT current_balance b FROM suppliers WHERE id=?').get(f.supplier).b,15);
  const cash=gl('1000'),ap=gl('2000');snapshot('supplier-credit-before-split');
  const split=await api('post','/api/payments',{supplier_id:f.supplier,payment_date:'2026-09-04',amount:60,payment_method:'credit',credit_note_id:note.id,purchase_allocations:[{purchase_id:targets[0].id,amount:30},{purchase_id:targets[1].id,amount:30}]});
  check('requested supplier credit split supported',split.status>=200&&split.status<300,true);
  check('supplier credit split no cash',gl('1000'),cash);check('supplier credit split company net AP unchanged',gl('2000'),ap);
  for(let index=0;index<targets.length;index++){
   const paid=db.prepare('SELECT COALESCE(SUM(a.amount),0) n FROM purchase_allocations a JOIN payments p ON p.id=a.payment_id WHERE a.purchase_id=? AND a.voided_at IS NULL AND p.voided_at IS NULL').get(targets[index].id).n;
   check('supplier split allocation target'+index,paid,30);
   const purchase=await ok('get',`/api/purchases/${targets[index].id}`);check('supplier split target balance'+index,purchase.balance_amount,index?15:0);
  }
  snapshot('supplier-credit-after-split-attempt');
 });
 await family('7c','supplier return cannot precede purchase',async()=>{
  const f=await fixture('supplier-early-return',10,10,'2026-09-10');const before=await ok('get','/api/reports/balance-sheet?asOfDate=2026-09-09');
  const returned=await api('post','/api/purchase-returns',{source_type:'PURCHASE',source_id:f.purchase,warehouse_id:f.warehouse,return_date:'2026-09-09',disposition:'credit_on_account',items:[{source_item_id:f.purchase,quantity:1}]});
  check('supplier return before purchase rejected',returned.status>=400&&returned.status<500,true);check('supplier early return stock unchanged',qty(f),10);
  const after=await ok('get','/api/reports/balance-sheet?asOfDate=2026-09-09');check('supplier early return historical inventory unchanged',after.assets.inventory-before.assets.inventory,0);check('supplier early return historical AP unchanged',after.liabilities.accounts_payable-before.liabilities.accounts_payable,0);snapshot('supplier-early-return');
 });
 await family('3b','unpaid and partial supplier returns',async()=>{
  for(const paid of [0,50]) {
   const f=await fixture('supplier-paid-'+paid,10);if(paid)await ok('post','/api/payments',{supplier_id:f.supplier,payment_date:'2026-09-02',amount:paid,payment_method:'cash',purchase_allocations:[{purchase_id:f.purchase,amount:paid}]});
   const n=paid?6:3;const ret=await ok('post','/api/purchase-returns',{source_type:'PURCHASE',source_id:f.purchase,warehouse_id:f.warehouse,return_date:'2026-09-03',disposition:'credit_on_account',items:[{source_item_id:f.purchase,quantity:n}]});
   const balance=db.prepare('SELECT current_balance FROM suppliers WHERE id=?').get(f.supplier).current_balance;
   check('supplier balance paid'+paid,balance,paid?-10:70);check('supplier stock paid'+paid,qty(f),10-n);
   const note=db.prepare("SELECT id FROM credit_notes WHERE source_type='PURCHASE_RETURN' AND source_id=?").get(ret.id);
   const response=await api('post','/api/supplier-refunds',{credit_note_id:note.id,refund_date:'2026-09-04',amount:paid?50.01:0.01,payment_method:'cash'});check('supplier collected-cash refund cap paid'+paid,response.status>=400&&response.status<500,true);
   if(paid)await ok('post','/api/supplier-refunds',{credit_note_id:note.id,refund_date:'2026-09-04',amount:10,payment_method:'cash'});
   snapshot('supplier-partial-'+paid);
  }
 });
 await family('5b','warehouse transfer and reversal',async()=>{
  const f=await fixture('warehouse-transfer',10);const inventory=gl('1200');const wh=await ok('post','/api/inventory/warehouses',{warehouse_code:'OR-SECOND',warehouse_name:'Second audit warehouse'});
  const transfer=await ok('post','/api/inventory/stock-transfers',{item_id:f.item,from_warehouse_id:f.warehouse,to_warehouse_id:wh.id,quantity:3});
  check('transfer company qty',qty(f),10);check('transfer company value',gl('1200'),inventory);snapshot('warehouse-transfer');
  await ok('post',`/api/inventory/stock-transfers/${transfer.out.movement_no}/void`,{reason:'audit'});check('transfer reversal company qty',qty(f),10);check('transfer reversal value',gl('1200'),inventory);snapshot('warehouse-transfer-void');
 });
 await family('7b','expiry aware FEFO and nonexpiry behavior',async()=>{
  const supplier=await ok('post','/api/suppliers',{supplier_code:'OR-FEFO',supplier_name:'FEFO supplier'});const customer=await ok('post','/api/customers',{customer_name:'FEFO customer',phone:'0300-0000001'});
  const item=await ok('post','/api/inventory/items',{item_code:'OR-FEFO',item_name:'Expiry audit',has_expiry:true});
  const warehouse=db.prepare("SELECT id FROM warehouses WHERE warehouse_code NOT IN ('DAMAGED','EXPIRED') ORDER BY id LIMIT 1").get().id;
  const f={item:item.id,supplier:supplier.id,customer:customer.id,warehouse};
  for(const [date,cost,expiry] of [['2026-09-01',10,'2026-12-31'],['2026-09-02',12,'2026-11-30']])await ok('post','/api/purchases',{item_id:item.id,supplier_id:supplier.id,warehouse_id:warehouse,quantity:2,unit_cost:cost,purchase_date:date,expiry_date:expiry});
  const cogs=gl('5000');await sale(f,2,20,'2026-10-20');check('FEFO selected earliest expiry cost',gl('5000')-cogs,2400);snapshot('fefo');
  const non=await fixture('nonexpiry',2);await ok('post','/api/purchases',{item_id:non.item,supplier_id:non.supplier,warehouse_id:non.warehouse,quantity:1,unit_cost:10,purchase_date:'2026-09-02',expiry_date:'2026-12-31'});
  check('nonexpiry ignores supplied expiry',db.prepare('SELECT COUNT(*) n FROM stock_batches WHERE item_id=? AND expiry_date IS NOT NULL').get(non.item).n,0);snapshot('nonexpiry');
 });
 await family('10b','negative stock and unavailable payment funds',async()=>{
  const f=await fixture('stock-funds',2);
  const stock=await api('post','/api/invoices',{customer_id:f.customer,invoice_date:'2026-09-02',warehouse_id:f.warehouse,items:[{item_id:f.item,warehouse_id:f.warehouse,quantity:3,unit_price:15}]});check('oversell rejected',stock.status>=400&&stock.status<500,true);check('oversell quantity',qty(f),2);
  const funds=await api('post','/api/payments',{supplier_id:f.supplier,payment_date:'2026-09-02',amount:1,payment_method:'bank',purchase_allocations:[{purchase_id:f.purchase,amount:1}]});check('unfunded bank payment rejected',funds.status>=400&&funds.status<500,true);snapshot('stock-funds');
 });
 await family('9b','year boundary opening movement closing',async()=>{
  const f=await fixture('year-boundary',10,10,'2025-12-30');const inv=await sale(f,3,15,'2025-12-31');await pay(f,inv,45,'2026-01-01');
  const dec=await ok('get','/api/reports/balance-sheet?asOfDate=2025-12-31');check('yearend inventory',dec.assets.inventory,70);check('yearend AR',dec.assets.accounts_receivable,45);check('yearend cash',dec.assets.cash,0);check('yearend net income',dec.equity.net_income_ytd,15);
  const jan=await ok('get','/api/reports/balance-sheet?asOfDate=2026-01-01');check('newyear AR',jan.assets.accounts_receivable,0);check('newyear cash',jan.assets.cash,45);check('newyear equity includes previous profit',jan.equity.total,15);
  const january=await ok('get','/api/reports/profit-loss?fromDate=2026-01-01&toDate=2026-01-31');check('receipt does not create January revenue',january.totalRevenue,0);check('January net profit',january.netProfit,0);snapshot('year-boundary');
 });
 await family('10c','partial receipt tax residual then receipt reversal',async()=>{
  const f=await fixture('tax-residual',1);const inventory=gl('1200'),tax=gl('1320'),ap=gl('2000');
  const po=await ok('post','/api/purchase-orders',{supplier_id:f.supplier,warehouse_id:f.warehouse,po_date:'2026-09-02',items:[{item_id:f.item,quantity:7,unit_price:3.33,input_tax_amount:1.01}]});await ok('post',`/api/purchase-orders/${po.id}/status`,{status:'Submitted'});
  const id=db.prepare('SELECT id FROM purchase_order_items WHERE po_id=?').get(po.id).id;
  await ok('post',`/api/purchase-orders/${po.id}/receipts`,{receipt_date:'2026-09-03',warehouse_id:f.warehouse,items:[{po_item_id:id,received_quantity:2}]});check('first receipt proportional input tax',gl('1320')-tax,29);check('first receipt inventory',gl('1200')-inventory,666);snapshot('tax-first-receipt');
  const second=await ok('post',`/api/purchase-orders/${po.id}/receipts`,{receipt_date:'2026-09-04',warehouse_id:f.warehouse,items:[{po_item_id:id,received_quantity:5}]});check('full input tax residual exact',gl('1320')-tax,101);check('full inventory exact',gl('1200')-inventory,2331);check('full receipt AP',gl('2000')-ap,-2432);snapshot('tax-complete');
  await ok('post',`/api/purchase-orders/${po.id}/receipts/${second.id}/void`,{reason:'audit'});check('reversed residual tax',gl('1320')-tax,29);check('reversed receipt inventory',gl('1200')-inventory,666);snapshot('tax-reversed');
 });
 await family('2b','credit applied across invoices prevents credit reversal',async()=>{
  const f=await fixture('credit-two-targets',20);const original=await sale(f,10);await pay(f,original,150);
  const ret=await ok('post',`/api/invoices/${original.id}/return`,{return_date:'2026-09-03',items:[{invoice_item_id:itemLine(original),return_quantity:4}],settlements:[{type:'credit',amount:60}]});
  const one=await sale(f,2,15,'2026-09-04',{credit_offset:30});const two=await sale(f,3,15,'2026-09-04',{credit_offset:30});
  check('first target fully credit paid',db.prepare('SELECT balance_amount b FROM invoices WHERE id=?').get(one.id).b,0);check('second target partly credit paid',db.prepare('SELECT balance_amount b FROM invoices WHERE id=?').get(two.id).b,15);
  const settlement=db.prepare("SELECT id FROM return_settlements WHERE return_id=? AND type='credit'").get(ret.returnId);
  snapshot('credit-before-void');
  const attempted=await api('post',`/api/return-settlements/${settlement.id}/void`,{});check('consumed credit settlement cannot reverse',attempted.status>=400&&attempted.status<500,true);snapshot('credit-two-targets');
  const reissued=await api('post',`/api/invoice-returns/${ret.returnId}/settle`,{allocations:[{type:'credit',amount:60}]});check('spent credit cannot be reissued',reissued.status>=400&&reissued.status<500,true);snapshot('credit-reissued');
  if(reissued.status===200) {const third=await sale(f,4,15,'2026-10-25',{credit_offset:60});check('third invoice must not get reused return credit',third.credit_offset??0,0);snapshot('credit-double-spend');}
 });
};
