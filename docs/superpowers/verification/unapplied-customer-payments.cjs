const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '../../..');
const Database = require(path.join(root, 'server/node_modules/better-sqlite3'));
const ts = require(path.join(root, 'server/node_modules/typescript'));
const plan = fs.readFileSync(path.join(root, 'docs/superpowers/plans/2026-10-16-unapplied-customer-payments.md'), 'utf8');
const spec = fs.readFileSync(path.join(root, 'docs/superpowers/specs/2026-10-16-unapplied-customer-payments-design.md'), 'utf8');
const blocks = [...plan.matchAll(/```(ts|sql)\n([\s\S]*?)```/g)].map(match => match[2]);
const specSql = [...spec.matchAll(/```sql\n([\s\S]*?)```/g)].map(match => match[1]);
const livePath = path.join(root, 'server/database/erp.db');
const baseline = '63e61c6a77991c4b1172abfd9da7135f80cd359b70a911f9c833c0379ee9b50f';
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'unapplied-plan-'));
const connections = [];
let failures = 0;
let passes = 0;

function fingerprint(filename) {
  return fs.existsSync(filename)
    ? crypto.createHash('sha256').update(fs.readFileSync(filename)).digest('hex')
    : null;
}

const before = [livePath, `${livePath}-wal`, `${livePath}-shm`].map(fingerprint);

function check(name, action) {
  try {
    action();
    passes += 1;
    console.log(`PASS ${name}`);
  } catch (error) {
    failures += 1;
    console.log(`FAIL ${name}: ${error.message}`);
  }
}

function snippet(marker) {
  const code = blocks.find(block => block.includes(marker));
  assert.ok(code, `missing snippet: ${marker}`);
  return code;
}

function evaluate(code, dirname = path.join(root, 'server/src/__tests__/helpers')) {
  const compiled = ts.transpileModule(code, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    reportDiagnostics: true,
  });
  assert.equal((compiled.diagnostics || []).filter(item => item.category === ts.DiagnosticCategory.Error).length, 0);
  const exports = {};
  vm.runInNewContext(compiled.outputText, { exports, require, console, __dirname: dirname });
  return exports;
}

function preflight(db) {
  const invalid = db.prepare(snippet('AS consumed_credit')).all();
  assert.equal(invalid.length, 0, 'unsupported historical consumption');
}

try {
  assert.equal(before[0], baseline, 'live database baseline changed; stop');
  const source = new Database(livePath, { readonly: true, fileMustExist: true });
  connections.push(source);
  const schema = source.prepare(`
    SELECT sql FROM sqlite_master
    WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%'
    ORDER BY CASE type WHEN 'table' THEN 0 WHEN 'index' THEN 1
                       WHEN 'view' THEN 2 ELSE 3 END, name
  `).all();
  const accounts = source.prepare('SELECT * FROM chart_of_accounts').all();
  source.close();

  function fixture(featureSchema = true) {
    const db = new Database(':memory:');
    connections.push(db);
    db.pragma('foreign_keys = ON');
    for (const row of schema) db.exec(row.sql);
    for (const row of accounts) {
      const columns = Object.keys(row);
      db.prepare(`INSERT INTO chart_of_accounts (${columns.join(',')}) VALUES (${columns.map(() => '?').join(',')})`).run(...Object.values(row));
    }
    if (featureSchema) {
      db.exec(snippet('INSERT INTO chart_of_accounts'));
      for (const name of ['customer_credit_sources', 'credit_source_consumptions', 'credit_applications']) {
        const sql = specSql.find(block => block.startsWith(`CREATE TABLE ${name} (`));
        assert.ok(sql, `missing spec DDL: ${name}`);
        db.exec(sql);
      }
      const alter = specSql.find(block => block.startsWith('ALTER TABLE payments ADD COLUMN payment_kind'));
      assert.ok(alter);
      db.exec(alter);
    }
    return db;
  }

  check('all TypeScript snippets pass semantic type checking', () => {
    const files = blocks.filter(block => /export function|export interface/.test(block));
    const options = {
      strict: true,
      noEmit: true,
      skipLibCheck: true,
      target: ts.ScriptTarget.ES2022,
      module: ts.ModuleKind.CommonJS,
      moduleResolution: ts.ModuleResolutionKind.Node10,
      types: ['node'],
      typeRoots: [path.join(root, 'server/node_modules/@types')],
      esModuleInterop: true,
    };
    const virtual = new Map(files.map((code, index) => [path.join(root, `server/plan-snippet-${index}.ts`), code]));
    const host = ts.createCompilerHost(options);
    const originalRead = host.readFile.bind(host);
    const originalExists = host.fileExists.bind(host);
    host.readFile = filename => virtual.get(filename) ?? originalRead(filename);
    host.fileExists = filename => virtual.has(filename) || originalExists(filename);
    host.getSourceFile = (filename, languageVersion) => {
      const text = host.readFile(filename);
      return text === undefined ? undefined : ts.createSourceFile(filename, text, languageVersion);
    };
    const diagnostics = ts.getPreEmitDiagnostics(ts.createProgram([...virtual.keys()], options, host));
    assert.equal(diagnostics.length, 0, ts.formatDiagnosticsWithColorAndContext(diagnostics, {
      getCanonicalFileName: filename => filename,
      getCurrentDirectory: () => root,
      getNewLine: () => '\n',
    }));
  });

  const guardCode = snippet('export function protectDatabaseConstructor');
  const guard = evaluate(guardCode);
  check('guard resolves the canonical server database', () => assert.equal(guard.resolveLiveDbPath(), livePath));
  check('intercepted native constructor rejects canonical and relative writes', () => {
    const Protected = guard.protectDatabaseConstructor(Database);
    assert.throws(() => new Protected(livePath), /refused/);
    assert.throws(() => new Protected(path.relative(process.cwd(), livePath)), /refused/);
  });
  check('guard rejects file and parent-directory symlink aliases', () => {
    const Protected = guard.protectDatabaseConstructor(Database);
    const alias = path.join(temporary, 'live-alias.db');
    fs.symlinkSync(livePath, alias);
    assert.throws(() => new Protected(alias), /refused/);
    const parent = path.join(temporary, 'live-parent');
    fs.symlinkSync(path.dirname(livePath), parent);
    assert.throws(() => new Protected(path.join(parent, 'erp.db')), /refused/);
  });
  check('guard rejects hardlink aliases on a disposable canonical database', () => {
    const helperDir = path.join(temporary, 'server/src/__tests__/helpers');
    const disposable = path.join(temporary, 'server/database/erp.db');
    fs.mkdirSync(helperDir, { recursive: true });
    fs.mkdirSync(path.dirname(disposable), { recursive: true });
    const seed = new Database(disposable);
    seed.close();
    const alias = path.join(temporary, 'hardlink.db');
    fs.linkSync(disposable, alias);
    const Protected = evaluate(guardCode, helperDir).protectDatabaseConstructor(Database);
    assert.throws(() => new Protected(alias), /refused/);
  });
  check('guard permits real writes to memory and disposable files', () => {
    const Protected = guard.protectDatabaseConstructor(Database);
    for (const filename of [':memory:', path.join(temporary, 'safe.db')]) {
      const db = new Protected(filename);
      try {
        db.exec('CREATE TABLE probe (amount INTEGER); INSERT INTO probe VALUES (500)');
        assert.equal(db.prepare('SELECT amount FROM probe').get().amount, 500);
      } finally {
        db.close();
      }
    }
  });
  check('guard permits readonly opens that SQLite prevents from writing', () => {
    const Protected = guard.protectDatabaseConstructor(Database);
    const db = new Protected(livePath, { readonly: true, fileMustExist: true });
    try {
      assert.equal(db.readonly, true);
    } finally {
      db.close();
    }
    const isolated = new Protected(path.join(temporary, 'safe.db'), { readonly: true });
    try {
      assert.throws(() => isolated.prepare('INSERT INTO probe VALUES (600)').run(), /readonly/);
    } finally {
      isolated.close();
    }
  });

  const seedHistory = evaluate(snippet('export function seedHistoricalLedger')).seedHistoricalLedger;
  const seedCustomers = evaluate(snippet('export function seedCustomers')).seedCustomers;
  const historical = fixture();
  check('historical fixture executes against the production schema', () => seedHistory(historical));
  check('historical IDs and ledger counts match the stated fixture', () => {
    assert.deepEqual(historical.prepare('SELECT id FROM customers ORDER BY id').all().map(row => row.id), [1, 12, 13, 14, 15]);
    assert.equal(historical.prepare("SELECT COUNT(*) n FROM customer_ledger WHERE transaction_type='RETURN'").get().n, 13);
    assert.equal(historical.prepare("SELECT COUNT(*) n FROM customer_ledger WHERE transaction_type='CREDIT_OFFSET'").get().n, 2);
  });
  check('historical refunds are debits and have zero credit', () => {
    const totals = historical.prepare("SELECT SUM(debit) debit, SUM(credit) credit FROM customer_ledger WHERE transaction_type='REFUND'").get();
    assert.deepEqual(totals, { debit: 4450, credit: 0 });
  });
  check('FIFO backfill preserves totals and every per-source ceiling', () => {
    preflight(historical);
    historical.exec(snippet('WITH ret AS'));
    const totals = historical.prepare('SELECT COUNT(*) n, SUM(credited_amount) credited, SUM(consumed_amount) consumed, SUM(remaining_amount) remaining, SUM(refundable_cash_amount) refundable FROM customer_credit_sources').get();
    assert.equal(totals.n, 13);
    assert.equal(Math.round(totals.credited * 100), 855020);
    assert.equal(Math.round(totals.consumed * 100), 180000);
    assert.equal(Math.round(totals.remaining * 100), 675020);
    assert.equal(totals.refundable, 0);
    assert.equal(historical.prepare('SELECT COUNT(*) n FROM customer_credit_sources WHERE consumed_amount > credited_amount').get().n, 0);
    const customer = historical.prepare('SELECT SUM(credited_amount) credited, SUM(consumed_amount) consumed, SUM(remaining_amount) remaining FROM customer_credit_sources WHERE customer_id=15').get();
    assert.deepEqual(customer, { credited: 2300, consumed: 1800, remaining: 500 });
    assert.deepEqual(historical.pragma('foreign_key_check'), []);
  });
  check('preflight rejects consumption without a supporting return', () => {
    const db = fixture();
    seedCustomers(db);
    db.prepare("INSERT INTO customer_ledger (customer_id,transaction_date,transaction_type,debit,credit,balance) VALUES (1,'2026-09-01','CREDIT_OFFSET',0,100,-100)").run();
    assert.throws(() => preflight(db), /unsupported/);
  });
  check('reconciliation reproduces every expected result under query_only', () => {
    historical.pragma('query_only = ON');
    const reconcile = evaluate(snippet('export function reconcileCustomerCredits')).reconcileCustomerCredits;
    const rows = reconcile(historical);
    assert.deepEqual(Array.from(rows, row => [row.customerId, Math.round(row.ledgerDerived * 100)]), [[1, 25020], [12, 10000], [13, 80000], [14, 120000], [15, -5000]]);
    assert.ok(rows.every(row => row.agrees === false));
    historical.pragma('query_only = OFF');
  });
  check('voided and reversed ledger rows are ignored', () => {
    const db = fixture();
    seedHistory(db);
    db.exec("INSERT INTO customer_ledger (customer_id,transaction_date,transaction_type,debit,credit,balance,voided) VALUES (1,'2026-09-01','RETURN',0,9999,0,1)");
    db.exec("INSERT INTO customer_ledger (customer_id,transaction_date,transaction_type,debit,credit,balance,reversed_by) VALUES (1,'2026-09-01','REFUND',9999,0,0,1)");
    const reconcile = evaluate(snippet('export function reconcileCustomerCredits')).reconcileCustomerCredits;
    assert.equal(Math.round(reconcile(db)[0].ledgerDerived * 100), 25020);
    preflight(db);
    db.exec(snippet('WITH ret AS'));
    assert.equal(db.prepare('SELECT COUNT(*) n FROM customer_credit_sources').get().n, 13);
  });
  check('feature seeds, generated remaining, refund drain and CHECK enforcement', () => {
    const db = fixture();
    seedCustomers(db);
    db.exec("INSERT INTO customer_credit_sources (customer_id,kind,credited_amount,refundable_cash_amount) VALUES (1,'UNAPPLIED_CASH',500,500)");
    db.exec('UPDATE customer_credit_sources SET consumed_amount=400,refundable_cash_amount=100 WHERE id=1');
    db.exec('UPDATE customer_credit_sources SET refunded_amount=100,refundable_cash_amount=0 WHERE id=1');
    assert.equal(db.prepare('SELECT remaining_amount n FROM customer_credit_sources WHERE id=1').get().n, 0);
    assert.throws(() => db.exec('UPDATE customer_credit_sources SET remaining_amount=5 WHERE id=1'), /generated/);
    assert.throws(() => db.exec('UPDATE customer_credit_sources SET refunded_amount=501 WHERE id=1'), /CHECK/);
    assert.throws(() => db.exec('UPDATE customer_credit_sources SET consumed_amount=-1 WHERE id=1'), /CHECK/);
    assert.throws(() => db.exec('UPDATE customer_credit_sources SET refundable_cash_amount=-1 WHERE id=1'), /CHECK/);
    assert.throws(() => db.exec('UPDATE customer_credit_sources SET refundable_cash_amount=1 WHERE id=1'), /CHECK/);
    assert.deepEqual(db.pragma('foreign_key_check'), []);
  });
  check('coverage matrix accounts for spec tests 1 through 35', () => {
    const matrix = plan.slice(plan.indexOf('## 9. Required coverage map'), plan.indexOf('## 10. Verification'));
    const covered = [...matrix.matchAll(/^\| ([\d, ]+) \|/gm)].flatMap(match => match[1].split(',').map(Number));
    assert.deepEqual([...new Set(covered)].sort((left, right) => left - right), Array.from({ length: 35 }, (_, index) => index + 1));
  });
} catch (error) {
  failures += 1;
  console.log(`FAIL setup: ${error.message}`);
} finally {
  for (const db of connections) if (db.open) db.close();
  fs.rmSync(temporary, { recursive: true, force: true });
  check('live main database and WAL/SHM fingerprints are unchanged', () => {
    assert.deepEqual([livePath, `${livePath}-wal`, `${livePath}-shm`].map(fingerprint), before);
  });
}

console.log(`${passes} passed; ${failures} failed`);
process.exitCode = failures ? 1 : 0;
