const Database = require('better-sqlite3');

const db = new Database('database/erp.db');
const ids = [11, 12, 13, 14, 16, 17, 18, 19];
const placeholders = ids.map(() => '?').join(',');

const tx = db.transaction(() => {
  const sm = db.prepare(`DELETE FROM stock_movements WHERE item_id IN (${placeholders})`).run(...ids);
  const sb = db.prepare(`DELETE FROM stock_balances WHERE item_id IN (${placeholders})`).run(...ids);
  const it = db.prepare(`DELETE FROM items WHERE id IN (${placeholders}) AND item_code LIKE 'E2E-OVR-%'`).run(...ids);
  console.log('deleted movements:', sm.changes, '| balances:', sb.changes, '| items:', it.changes);
});
tx();

console.log('integrity_check:', db.pragma('integrity_check', { simple: true }));
console.log('foreign_key_check violations:', db.prepare('PRAGMA foreign_key_check').all().length);
db.close();
