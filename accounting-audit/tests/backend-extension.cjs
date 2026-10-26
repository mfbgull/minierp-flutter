const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
const { createIsolatedAuditFixture, startAuditSession } = require('./lib/isolated-fixture.cjs');
const { run, database, db, evidence } = createIsolatedAuditFixture(path.join(root, 'accounting-audit/evidence/backend-extension-run-'));
let cleanup;
async function main(){
  const { api, net } = await startAuditSession({ database, db }, evidence, value => { cleanup = value; });
  let res=await api('post','/api/owner-equity/capital',{amount:1000,capital_date:'2026-09-01',payment_method:'Bank'});assert.equal(res.status,201);
  const warehouse=db.prepare("SELECT id FROM warehouses WHERE is_active=1 AND warehouse_code NOT IN ('EXPIRED','DAMAGED') ORDER BY id LIMIT 1").get().id;
  async function item(code,price){const x=await api('post','/api/inventory/items',{item_code:code,item_name:code,unit_of_measure:'Nos',is_purchased:true,is_manufactured:true,standard_cost:10,standard_selling_price:price});assert.equal(x.status,201);return x.body.id;}
  const input=await item('EXT-RAW',100);const outA=await item('EXT-OUT-A',30);const outB=await item('EXT-OUT-B',10);
  res=await api('post','/api/suppliers',{supplier_code:'EXT-SUP',supplier_name:'Extension supplier',phone:'03001234567'});assert.equal(res.status,201);const supplier=res.body.id??res.body.data?.id;
  res=await api('post','/api/purchases',{item_id:input,warehouse_id:warehouse,quantity:10,unit_cost:10,purchase_date:'2026-09-02',supplier_id:supplier});assert.equal(res.status,201);
  function snapshot(label){
    const state={label,accounts:Object.fromEntries(['1010','1200','2000','2200','3200','3300','6000','6100','7000','7100','7200'].map(code=>[code,net(code)])),stocks:db.prepare('SELECT item_id,warehouse_id,quantity FROM stock_balances ORDER BY item_id,warehouse_id').all(),batches:db.prepare('SELECT id,item_id,source_type,source_id,quantity_original,quantity_remaining,unit_cost FROM stock_batches ORDER BY id').all(),journal:db.prepare('SELECT j.*,a.code FROM journal_lines j JOIN chart_of_accounts a ON a.id=j.account_id ORDER BY j.id').all(),headers:db.prepare('SELECT * FROM journal_entries ORDER BY id').all(),movements:db.prepare('SELECT * FROM stock_movements ORDER BY id').all()};
    fs.writeFileSync(path.join(run,label+'.json'),JSON.stringify(state,null,2));return state;
  }
  const initial=snapshot('01-before-production');
  res=await api('post','/api/productions',{warehouse_id:warehouse,production_date:'2026-09-03',input_items:[{item_id:input,quantity:6}],outputs:[{item_id:outA,quantity:2},{item_id:outB,quantity:3}],overhead_cost:30});assert.equal(res.status,201);const production=res.body.id??res.body.data?.id;assert(production);
  const produced=snapshot('02-production-overhead');const outputs=db.prepare('SELECT * FROM production_outputs ORDER BY id').all();
  assert.equal(produced.accounts['1200'],130);assert.equal(produced.accounts['2200'],-30);assert.equal(produced.accounts['7000'],0);assert.equal(produced.accounts['6000'],0);assert.deepEqual(outputs.map(x=>x.allocated_cost),[60,30]);
  res=await api('delete',`/api/productions/${production}`,{reason:'Audit reversal'});assert.equal(res.status,200);const reversed=snapshot('03-production-reversed');
  assert.deepEqual(reversed.accounts,initial.accounts);assert.equal(reversed.stocks.find(x=>x.item_id===input).quantity,10);assert.equal(reversed.stocks.find(x=>x.item_id===outA).quantity,0);assert.equal(reversed.stocks.find(x=>x.item_id===outB).quantity,0);
  const secondDelete=await api('delete',`/api/productions/${production}`,{});assert.equal(secondDelete.status,404);
  evidence.scenarios.push({id:'BACKEND-EXT-PRODUCTION-OVERHEAD-REVERSE',status:'PASS',expected:{inputCost:60,overhead:30,allocation:[60,30],inventoryAfter:130,payableAfter:-30,clearing:0,reversalAccountsEqualInitial:true,repeatedDelete:404},actual:{outputs,produced:produced.accounts,reversed:reversed.accounts},artifacts:['01-before-production.json','02-production-overhead.json','03-production-reversed.json']});
  res=await api('post','/api/owner-equity/withdrawals',{withdrawal_date:'2026-09-04',kind:'goods',items:[{item_id:input,warehouse_id:warehouse,quantity:3}]});assert.equal(res.status,201);const goods=res.body.data.id;assert.equal(res.body.data.amount,30);const goodsState=snapshot('04-owner-goods');assert.equal(goodsState.accounts['3300'],30);assert.equal(goodsState.accounts['1200'],70);assert.equal(goodsState.accounts['6000'],0);
  res=await api('post','/api/owner-equity/withdrawals',{withdrawal_date:'2026-09-04',kind:'cash',amount:50,payment_method:'Bank'});assert.equal(res.status,201);const cash=res.body.data.id;const cashState=snapshot('05-owner-cash');assert.equal(cashState.accounts['3300'],80);assert.equal(cashState.accounts['1010'],950);
  res=await api('delete',`/api/owner-equity/withdrawals/${goods}`,{reason:'Audit reversal'});assert.equal(res.status,200);
  res=await api('delete',`/api/owner-equity/withdrawals/${cash}`,{reason:'Audit reversal'});assert.equal(res.status,200);const ownerReversed=snapshot('06-owner-reversed');assert.deepEqual(ownerReversed.accounts,initial.accounts);assert.equal(ownerReversed.stocks.find(x=>x.item_id===input).quantity,10);
  evidence.scenarios.push({id:'BACKEND-EXT-OWNER-DRAWINGS',status:'PASS',expected:{goodsCost:30,goodsSellingValueNotUsed:300,cashDraw:50,combinedDrawings:80,reversalAccountsEqualInitial:true},actual:{goods:goodsState.accounts,cash:cashState.accounts,reversed:ownerReversed.accounts},artifacts:['04-owner-goods.json','05-owner-cash.json','06-owner-reversed.json']});
  res=await api('post','/api/inventory/physical-counts',{warehouse_id:warehouse,count_date:'2026-09-05',notes:'Audit count'});assert.equal(res.status,201);const count=res.body.id;assert(count);
  res=await api('post',`/api/inventory/physical-counts/${count}/items`,{item_id:input,counted_quantity:8});assert.equal(res.status,200);
  res=await api('post',`/api/inventory/physical-counts/${count}/complete`,{});assert.equal(res.status,200);const counted=snapshot('07-count-completed');assert.equal(counted.stocks.find(x=>x.item_id===input).quantity,8);assert.equal(counted.accounts['1200'],80);assert.equal(counted.accounts['7200'],20);
  res=await api('post',`/api/inventory/physical-counts/${count}/correct`,{corrections:[{item_id:input,counted_quantity:9}]});assert.equal(res.status,200);const corrected=snapshot('08-count-corrected');assert.equal(corrected.stocks.find(x=>x.item_id===input).quantity,9);assert.equal(corrected.accounts['1200'],90);assert.equal(corrected.accounts['7200'],10);
  const duplicateCorrection=await api('post',`/api/inventory/physical-counts/${count}/correct`,{corrections:[{item_id:input,counted_quantity:10}]});assert.equal(duplicateCorrection.status,400);assert.deepEqual(snapshot('09-count-repeat-rejected').accounts,corrected.accounts);
  evidence.scenarios.push({id:'BACKEND-EXT-PHYSICAL-COUNT-CORRECT',status:'PASS',expected:{initialQuantity:10,countedQuantity:8,correctedQuantity:9,lossAfterCount:20,lossAfterCorrection:10,repeatCorrection:400},actual:{counted:counted.accounts,corrected:corrected.accounts,repeatStatus:duplicateCorrection.status},artifacts:['07-count-completed.json','08-count-corrected.json','09-count-repeat-rejected.json']});
  evidence.integrity=db.pragma('integrity_check');evidence.foreignKeys=db.pragma('foreign_key_check');evidence.unbalanced=db.prepare('SELECT * FROM journal_entry_balances WHERE balance_cents!=0').all();assert.deepEqual(evidence.unbalanced,[]);assert.deepEqual(evidence.foreignKeys,[]);
  evidence.counts=db.prepare('SELECT * FROM physical_counts').all();evidence.countItems=db.prepare('SELECT * FROM physical_count_items').all();
}
main().then(()=>{evidence.completed=true;}).catch(error=>{evidence.error={message:error.message,stack:error.stack};process.exitCode=1;}).finally(()=>{fs.writeFileSync(path.join(run,'results.json'),JSON.stringify(evidence,null,2));fs.writeFileSync(path.join(root,'accounting-audit/evidence/backend-extension-latest-run.txt'),run+'\n');db.close();if(cleanup)cleanup();console.log(JSON.stringify({run,completed:evidence.completed,scenarios:evidence.scenarios,error:evidence.error},null,2));});
