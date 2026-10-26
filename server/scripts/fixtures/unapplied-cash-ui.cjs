const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

function validateEnvironment(environment) {
  if (environment.DATABASE_PATH || (environment.NODE_ENV && environment.NODE_ENV !== 'test')) {
    throw new Error('Fixture requires an owned fresh database and test environment');
  }
}

async function start() {
  validateEnvironment(process.env);
  const serverRoot = path.resolve(__dirname, '../..');
  process.chdir(serverRoot);
  const root = path.join(serverRoot, '.tmp-test');
  fs.mkdirSync(root, { recursive: true });
  const directory = fs.mkdtempSync(path.join(root, 'ui-f7-'));
  const marker = crypto.randomUUID();
  fs.writeFileSync(path.join(directory, 'fixture-id'), marker, { flag: 'wx' });
  process.env.NODE_ENV = 'test';
  process.env.DATABASE_PATH = directory;
  process.env.JWT_SECRET = 'ui-f7-isolated-test-secret';
  process.env.DEFAULT_ADMIN_PASSWORD = 'ui-f7-isolated-password';
  require('ts-node/register/transpile-only');
  const location = require.resolve('better-sqlite3');
  const original = require(location);
  const guard = require('../../src/__tests__/helpers/liveDbGuard');
  require.cache[location].exports = guard.protectDatabaseConstructor(original);
  const canonical = guard.resolveLiveDbPath();
  const fingerprints = () => [canonical, `${canonical}-wal`, `${canonical}-shm`].map(filename =>
    fs.existsSync(filename) ? crypto.createHash('sha256').update(fs.readFileSync(filename)).digest('hex') : null);
  const before = fingerprints();
  const database = require('../../src/config/database');
  database.applyPendingMigrations();
  await database.dbSeedReady;
  const db = database.default;
  const accounting = require('../../src/services/accountingService').default;
  const checks = require('../../src/__tests__/helpers/accountingInvariants');
  const { pruneIdempotencyKeys } = require('../../src/utils/idempotency');
  const { api, control } = createFixtureApps({ db, accounting, checks, pruneIdempotencyKeys, directory, marker, before, fingerprints, app: require('../../src/app').default });
  const apiServer = api.listen(4327, '127.0.0.1');
  const controlServer = control.listen(4328, '127.0.0.1');
  const shutdown = () => {
    apiServer.close();
    controlServer.close();
    db.close();
    const unchanged = JSON.stringify(before) === JSON.stringify(fingerprints());
    console.log(JSON.stringify({ stopped: true, canonicalUnchanged: unchanged, directory }));
    process.exit(unchanged ? 0 : 1);
  };
  process.once('SIGINT', shutdown);
  process.once('SIGTERM', shutdown);
  console.log(JSON.stringify({ ready: true, directory, marker, api: 'http://127.0.0.1:4327/api' }));
}

function createFixtureApps({ db, accounting, checks, pruneIdempotencyKeys, directory, marker, before, fingerprints, app }) {
  const express = require('express');
  const date = new Date().toISOString().slice(0, 10);
  let dropPath = null;
  let unsupported = false;
  let offlineReads = false;
  let writeRequests = 0;
  const api = express();
  api.use((request, response, next) => {
    if (request.method === 'POST' && request.path.includes('unapplied-cash')) writeRequests++;
    if (unsupported && request.path === '/api/unapplied-cash/capabilities') {
      return response.json({ success: true, data: {} });
    }
    if (offlineReads && request.method === 'GET' && request.path.includes('unapplied-cash')) {
      request.socket.destroy();
      return;
    }
    if (dropPath === request.path && request.method === 'POST') {
      dropPath = null;
      const send = response.json.bind(response);
      response.json = body => {
        if (response.statusCode < 300) {
          request.socket.destroy();
          return response;
        }
        return send(body);
      };
    }
    next();
  });
  api.use(app);
  const control = express();
  control.use(express.json({ limit: '16kb' }));
  control.use((request, response, next) => {
    if (request.get('X-Fixture-Token') !== 'mini-erp-f7-local') return response.sendStatus(403);
    if (fs.readFileSync(path.join(directory, 'fixture-id'), 'utf8') !== marker) throw new Error('Fixture marker mismatch');
    next();
  });
  control.get('/health', (request, response) => response.json({
    fixture: 'mini-erp-unapplied-cash-f7', marker, api: 'http://127.0.0.1:4327/api', directory, date,
  }));
  control.post('/command', (request, response) => {
    const input = request.body;
    switch (input.action) {
      case 'role': {
        if (!['read', 'partial'].includes(input.kind)) return response.sendStatus(400);
        const username = `f7-${crypto.randomUUID()}`;
        const roleId = Number(db.prepare('INSERT INTO roles(role_name) VALUES (?)').run(username).lastInsertRowid);
        const actions = input.kind === 'partial' ? ['read', 'update'] : ['read'];
        for (const action of actions) db.prepare('INSERT INTO role_permissions(role_id,permission_id) SELECT ?,id FROM permissions WHERE module=? AND action=?').run(roleId, 'payments', action);
        const userId = Number(db.prepare("INSERT INTO users(username,email,password_hash,full_name,role,role_id) SELECT ?,?,password_hash,?,'user',? FROM users WHERE username='admin'").run(username, `${username}@fixture.invalid`, username, roleId).lastInsertRowid);
        const user = { id: userId, username, role: 'user', permissions: actions.map(action => ({ module: 'payments', action })) };
        return response.json({ user, token: require('../../src/middleware/auth').generateToken(user) });
      }
      case 'customer': {
        const code = `F7-${crypto.randomUUID()}`;
        const result = db.prepare('INSERT INTO customers(customer_code,customer_name) VALUES (?,?)').run(code, 'F7 runtime customer');
        return response.json(db.prepare('SELECT * FROM customers WHERE id=?').get(Number(result.lastInsertRowid)));
      }
      case 'invoice': {
        const customerId = Number(input.customerId);
        if (!db.prepare('SELECT id FROM customers WHERE id=?').get(customerId)) return response.sendStatus(404);
        const result = db.transaction(() => {
          const number = `INV-F7-${crypto.randomUUID()}`;
          const result = db.prepare('INSERT INTO invoices(invoice_no,customer_id,invoice_date,total_amount,balance_amount,paid_amount) VALUES (?,?,?,400,400,0)').run(number, customerId, date);
          const invoiceId = Number(result.lastInsertRowid);
          db.prepare('INSERT INTO customer_ledger(customer_id,transaction_date,transaction_type,reference_no,debit,credit,balance) VALUES (?,?,\'INVOICE\',?,400,0,400)').run(customerId, date, number);
          db.prepare('UPDATE customers SET current_balance=current_balance+400 WHERE id=?').run(customerId);
          accounting.postEntry(db, { entry_date: date, description: 'F7 isolated fixture invoice', reference_type: 'INVOICE', reference_id: invoiceId,
            lines: [{ account_id: accounting.getAccountByCode(db, '1100').id, debit: 400 }, { account_id: accounting.getAccountByCode(db, '4000').id, credit: 400 }] });
          return invoiceId;
        })();
        return response.json({ invoiceId: result });
      }
      case 'drop':
        if (!/^\/api\/customers\/\d+\/unapplied-cash$/.test(input.path)) return response.sendStatus(400);
        dropPath = input.path;
        return response.json({ armed: true });
      case 'capabilities':
        unsupported = input.unsupported === true;
        return response.json({ unsupported });
      case 'period':
        db.prepare('UPDATE accounting_periods SET status=? WHERE start_date<=? AND end_date>=?').run(input.closed === true ? 'closed' : 'open', date, date);
        return response.json({ closed: input.closed === true });
      case 'offline':
        offlineReads = input.enabled === true;
        return response.json({ offlineReads });
      case 'prune': {
        db.prepare("UPDATE idempotency_keys SET completed_at='2020-01-01' WHERE completed_at IS NOT NULL").run();
        const pruned = pruneIdempotencyKeys(db, 30, new Date('2020-03-01T00:00:00Z'));
        return response.json({ pruned, retained: db.prepare('SELECT COUNT(*) count FROM idempotency_keys').get().count });
      }
      default: return response.sendStatus(400);
    }
  });
  control.get('/status', (request, response) => {
    const violations = {};
    for (const name of ['customerArImbalances', 'supplierApImbalances', 'stockImbalances', 'arImbalances', 'apImbalances', 'inventoryImbalances', 'cashImbalances', 'orphanSourceBatches', 'unappliedLiabilityImbalances', 'creditSourceConsumptionImbalances', 'creditSourceBoundsImbalances', 'receiptAllocationImbalances']) {
      violations[name] = checks[name](db);
    }
    response.json({
      gl: checks.glImbalances(db), violations, writeRequests,
      payments: db.prepare('SELECT id,customer_id,amount,payment_kind,voided_at FROM payments ORDER BY id').all(),
      sources: db.prepare('SELECT id,customer_id,origin_payment_id,consumed_amount,refunded_amount,remaining_amount,voided_at FROM customer_credit_sources').all(),
      invoices: db.prepare('SELECT id,customer_id,paid_amount,balance_amount FROM invoices').all(),
      customers: db.prepare('SELECT id,current_balance,credit_balance FROM customers').all(),
      canonicalUnchanged: JSON.stringify(before) === JSON.stringify(fingerprints()),
    });
  });
  return { api, control };
}
module.exports = { validateEnvironment, createFixtureApps };
if (require.main === module) start().catch(error => { console.error(error.message); process.exitCode = 1; });
