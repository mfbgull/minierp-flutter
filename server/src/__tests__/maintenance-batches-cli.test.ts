import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';

describe('batch backfill CLI with fresh historical-shape fixtures', () => {
  const originalPath = process.env.DATABASE_PATH;
  let directory: string;
  let db: Database.Database;
  let output: jest.SpyInstance;

  beforeEach(() => {
    directory = fs.mkdtempSync(path.join(__dirname, '../../.tmp-test/maintenance-batches-'));
    process.env.DATABASE_PATH = directory;
    db = new Database(path.join(directory, 'erp.db'));
    output = jest.spyOn(console, 'log').mockImplementation(() => undefined);
    db.exec(`
      CREATE TABLE items(id INTEGER PRIMARY KEY,standard_cost REAL);
      CREATE TABLE productions(id INTEGER PRIMARY KEY,production_no TEXT,output_item_id INTEGER,
        output_quantity REAL,warehouse_id INTEGER,production_date TEXT,overhead_cost REAL,
        batch_no TEXT,unit_cost REAL,total_material_cost REAL,total_batch_cost REAL);
      CREATE TABLE production_inputs(production_id INTEGER,item_id INTEGER,quantity REAL);
      CREATE TABLE purchases(id INTEGER PRIMARY KEY,purchase_no TEXT,item_id INTEGER,warehouse_id INTEGER,
        quantity REAL,unit_cost REAL,purchase_date TEXT,batch_no TEXT);
      CREATE TABLE stock_movements(id INTEGER PRIMARY KEY,reference_docno TEXT,movement_type TEXT,
        quantity REAL,unit_cost REAL,batch_id INTEGER);
      CREATE TABLE stock_batches(id INTEGER PRIMARY KEY,batch_no TEXT,item_id INTEGER,warehouse_id INTEGER,
        source_type TEXT,source_id INTEGER,quantity_original REAL,quantity_remaining REAL,unit_cost REAL,received_date TEXT);
    `);
  });

  afterEach(() => {
    db.close();
    fs.rmSync(directory, { recursive: true, force: true });
    process.env.DATABASE_PATH = originalPath;
    output.mockRestore();
  });

  function run(): void {
    jest.isolateModules(() => { jest.requireActual<Record<string, never>>('../scripts/backfill-batches'); });
  }

  test('costs productions from material plus overhead, links movements, and skips existing batches', () => {
    db.exec(`
      INSERT INTO items VALUES(1,5),(2,NULL);
      INSERT INTO productions(id,production_no,output_item_id,output_quantity,warehouse_id,production_date,overhead_cost)
        VALUES(1,'PRD-1',1,2,1,'2026-01-01',4),(2,'PRD-2',1,0,1,'2026-01-02',NULL),
        (3,'PRD-3',1,0,1,'2026-01-03',NULL);
      INSERT INTO production_inputs VALUES(1,1,2),(1,2,3);
      INSERT INTO stock_movements VALUES(1,'PRD-1','PRODUCTION',2,999,NULL),
        (2,'PRD-2','PRODUCTION',1,8,NULL),(3,'PUR-1','PURCHASE',4,7,NULL);
      INSERT INTO purchases VALUES(1,'PUR-1',1,1,4,7,'2026-01-04',NULL),(2,'PUR-2',1,1,1,3,'2026-01-05',NULL);
    `);
    run();
    expect(db.prepare('SELECT source_type,source_id,quantity_remaining,unit_cost FROM stock_batches ORDER BY id').all()).toEqual([
      { source_type: 'PRODUCTION', source_id: 1, quantity_remaining: 2, unit_cost: 7 },
      { source_type: 'PRODUCTION', source_id: 2, quantity_remaining: 0, unit_cost: 8 },
      { source_type: 'PRODUCTION', source_id: 3, quantity_remaining: 0, unit_cost: 0 },
      { source_type: 'PURCHASE', source_id: 1, quantity_remaining: 4, unit_cost: 7 },
      { source_type: 'PURCHASE', source_id: 2, quantity_remaining: 1, unit_cost: 3 },
    ]);
    expect(db.prepare('SELECT batch_id FROM stock_movements ORDER BY id').all()).toEqual([{ batch_id: 1 }, { batch_id: 2 }, { batch_id: 4 }]);
    expect(db.prepare('SELECT total_material_cost,total_batch_cost FROM productions WHERE id=1').get())
      .toEqual({ total_material_cost: 10, total_batch_cost: 14 });
    const batches = db.prepare('SELECT * FROM stock_batches').all();
    run();
    expect(db.prepare('SELECT * FROM stock_batches').all()).toEqual(batches);
    expect(output).toHaveBeenLastCalledWith('\n=== Complete: 0 batches created ===');
  });
});
