const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
const run = fs.mkdtempSync(path.join(root, 'accounting-audit/evidence/backend-count-risk-run-'));
process.env.NODE_ENV = 'test';
process.env.DATABASE_PATH = run;
process.env.JWT_SECRET = 'backend-audit-fixture-secret-only-2026';
process.env.DEFAULT_ADMIN_PASSWORD = 'Backend-audit-fixture-password-2026!';
process.env.LOG_DIR = path.join(run, 'logs');
const sqlitePath = require.resolve(path.join(root, 'server/node_modules/better-sqlite3'));
const Sqlite = require(sqlitePath);
require.cache[sqlitePath].exports = new Proxy(Sqlite, {construct(target, args) {
  const file = path.resolve(args[0]);
  assert(file.startsWith(run + path.sep), `Refusing DB outside disposable fixture: ${file}`);
  return Reflect.construct(target, args);
}});
require(path.join(root, 'server/node_modules/ts-node')).register({project:path.join(root,'server/tsconfig.json'),transpileOnly:true});
const database = require(path.join(root,'server/src/config/database'));
const db=database.default;
const evidence={run,guard:'Every SQLite constructor restricted to newly created run directory',api:[],scenarios:[]};
let cleanup;
async function main(){
  database.applyPendingMigrations(); await database.dbSeedReady;
  const app=require(path.join(root,'server/src/app')).default;
  const request=require(path.join(root,'server/node_modules/supertest'));
  cleanup=()=>{require(path.join(root,'server/src/middleware/rateLimiter')).shutdownRateLimiters();require(path.join(root,'server/src/utils/logger')).default.close();};
  const login=await request(app).post('/api/auth/login').send({username:'admin',password:process.env.DEFAULT_ADMIN_PASSWORD});
  assert.equal(login.status,200);
  const cookie=login.headers['set-cookie'].map(x=>x.split(';')[0]).join('; ');
  async function api(method,url,body){const res=await request(app)[method](url).set('Cookie',cookie).send(body);evidence.api.push({method,url,body,status:res.status,response:res.body});return res;}
  function net(code,until='9999-12-31'){return db.prepare('SELECT ROUND(COALESCE(SUM(j.debit-j.credit),0),2) AS amount FROM journal_lines j JOIN chart_of_accounts a ON a.id=j.account_id WHERE a.code=? AND j.voided=0 AND j.line_date<=?').get(code,until).amount;}
  const warehouse=db.prepare("SELECT id FROM warehouses WHERE is_active=1 AND warehouse_code NOT IN ('EXPIRED','DAMAGED') ORDER BY id LIMIT 1").get().id;
  async function item(code){const x=await api('post','/api/inventory/items',{item_code:code,item_name:code,unit_of_measure:'Nos',is_purchased:true,standard_cost:10,standard_selling_price:50});assert.equal(x.status,201);return x.body.id;}
  let res=await api('post','/api/suppliers',{supplier_code:'COUNT-SUP',supplier_name:'Count supplier',phone:'03001234567'});assert.equal(res.status,201);const supplier=res.body.id??res.body.data?.id;
  const mixed=await item('MIXED-COUNT');
  async function purchase(item_id,quantity,unit_cost,purchase_date){const x=await api('post','/api/purchases',{item_id,warehouse_id:warehouse,quantity,unit_cost,purchase_date,supplier_id:supplier});assert.equal(x.status,201);}
  await purchase(mixed,5,10,'2026-09-01');await purchase(mixed,5,20,'2026-09-02');
  function state(label){const x={label,glInventory:net('1200'),loss:net('7200'),stocks:db.prepare('SELECT * FROM stock_balances ORDER BY item_id').all(),batches:db.prepare('SELECT id,item_id,quantity_original,quantity_remaining,unit_cost FROM stock_batches ORDER BY id').all(),journal:db.prepare('SELECT j.*,a.code FROM journal_lines j JOIN chart_of_accounts a ON a.id=j.account_id ORDER BY j.id').all(),counts:db.prepare('SELECT * FROM physical_counts').all(),countItems:db.prepare('SELECT * FROM physical_count_items').all(),movements:db.prepare('SELECT * FROM stock_movements ORDER BY id').all()};fs.writeFileSync(path.join(run,label+'.json'),JSON.stringify(x,null,2));return x;}
  res=await api('post','/api/inventory/physical-counts',{warehouse_id:warehouse,count_date:'2026-09-03'});assert.equal(res.status,201);const count=res.body.id;
  res=await api('post',`/api/inventory/physical-counts/${count}/items`,{item_id:mixed,counted_quantity:2});assert.equal(res.status,200);
  res=await api('post',`/api/inventory/physical-counts/${count}/complete`,{});assert.equal(res.status,200);const completed=state('01-mixed-count-completed');assert.equal(completed.glInventory,40);assert.equal(completed.loss,110);
  res=await api('post',`/api/inventory/physical-counts/${count}/correct`,{corrections:[{item_id:mixed,counted_quantity:8}]});const correctionStatus=res.status;const correctionResponse=res.body;const corrected=state('02-mixed-count-corrected');
  const batchValue=Math.round(corrected.batches.filter(x=>x.item_id===mixed).reduce((sum,x)=>sum+x.quantity_remaining*x.unit_cost,0)*100)/100;
  evidence.scenarios.push({id:'BACKEND-COUNT-MIXED-COST-CORRECTION',expected:{quantity:8,batches:[{quantity:3,cost:10},{quantity:5,cost:20}],batchValue:130,glInventory:130,loss:20},actual:{status:correctionStatus,response:correctionResponse,batchValue,glInventory:corrected.glInventory,loss:corrected.loss,batches:corrected.batches},defectReproduced:correctionStatus!==200||batchValue!==130,artifacts:['01-mixed-count-completed.json','02-mixed-count-corrected.json']});
  const other=await item('OTHER-COUNT');await purchase(other,10,10,'2026-09-04');
  res=await api('post','/api/inventory/physical-counts',{warehouse_id:warehouse,count_date:'2026-09-05'});assert.equal(res.status,201);const second=res.body.id;
  for(const [item_id,counted_quantity] of [[mixed,1],[other,8]]){res=await api('post',`/api/inventory/physical-counts/${second}/items`,{item_id,counted_quantity});assert.equal(res.status,200);}
  res=await api('post',`/api/inventory/physical-counts/${second}/complete`,{});assert.equal(res.status,200);const before=state('03-two-item-count-completed');
  res=await api('post',`/api/inventory/physical-counts/${second}/correct`,{corrections:[{item_id:mixed,counted_quantity:2}]});assert.equal(res.status,200);const after=state('04-partial-item-correction');
  const otherStock=after.stocks.find(x=>x.item_id===other).quantity;const otherCount=after.countItems.find(x=>x.count_id===second&&x.item_id===other);
  evidence.scenarios.push({id:'BACKEND-COUNT-PARTIAL-CORRECTION',expected:{uncorrectedItemQuantity:8,uncorrectedItemCountedQuantity:8},actual:{otherStock,otherCount,beforeInventory:before.glInventory,afterInventory:after.glInventory,beforeLoss:before.loss,afterLoss:after.loss},defectReproduced:otherStock!==8,artifacts:['03-two-item-count-completed.json','04-partial-item-correction.json']});
  evidence.integrity=db.pragma('integrity_check');evidence.foreignKeys=db.pragma('foreign_key_check');evidence.unbalanced=db.prepare('SELECT * FROM journal_entry_balances WHERE balance_cents!=0').all();

}
main().then(()=>{evidence.completed=true;}).catch(error=>{evidence.error={message:error.message,stack:error.stack};process.exitCode=1;}).finally(()=>{fs.writeFileSync(path.join(run,'results.json'),JSON.stringify(evidence,null,2));fs.writeFileSync(path.join(root,'accounting-audit/evidence/backend-count-risk-latest-run.txt'),run+'\n');db.close();if(cleanup)cleanup();console.log(JSON.stringify({run,completed:evidence.completed,scenarios:evidence.scenarios,error:evidence.error},null,2));});
