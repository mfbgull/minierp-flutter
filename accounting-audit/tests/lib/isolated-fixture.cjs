const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..');

function createIsolatedAuditFixture(runPrefix) {
  const run = fs.mkdtempSync(runPrefix);
  process.env.NODE_ENV = 'test';
  process.env.DATABASE_PATH = run;
  process.env.JWT_SECRET = 'backend-audit-fixture-secret-only-2026';
  process.env.DEFAULT_ADMIN_PASSWORD = 'Backend-audit-fixture-password-2026!';
  process.env.LOG_DIR = path.join(run, 'logs');
  const sqlitePath = require.resolve(path.join(root, 'server/node_modules/better-sqlite3'));
  const Sqlite = require(sqlitePath);
  require.cache[sqlitePath].exports = new Proxy(Sqlite, {
    construct(target, args) {
      const file = path.resolve(args[0]);
      assert(file.startsWith(run + path.sep), `Refusing DB outside disposable fixture: ${file}`);
      return Reflect.construct(target, args);
    },
  });
  require(path.join(root, 'server/node_modules/ts-node')).register({
    project: path.join(root, 'server/tsconfig.json'),
    transpileOnly: true,
  });
  const database = require(path.join(root, 'server/src/config/database'));
  const evidence = {
    run,
    guard: 'Every SQLite constructor restricted to newly created run directory',
    api: [],
    scenarios: [],
  };
  return { run, database, db: database.default, evidence };
}

async function startAuditSession({ database, db }, evidence, registerCleanup) {
  database.applyPendingMigrations();
  await database.dbSeedReady;
  const app = require(path.join(root, 'server/src/app')).default;
  const request = require(path.join(root, 'server/node_modules/supertest'));
  registerCleanup(() => {
    require(path.join(root, 'server/src/middleware/rateLimiter')).shutdownRateLimiters();
    require(path.join(root, 'server/src/utils/logger')).default.close();
  });
  const login = await request(app).post('/api/auth/login').send({
    username: 'admin', password: process.env.DEFAULT_ADMIN_PASSWORD,
  });
  assert.equal(login.status, 200);
  const cookie = login.headers['set-cookie'].map(x => x.split(';')[0]).join('; ');
  async function api(method, url, body) {
    const res = await request(app)[method](url).set('Cookie', cookie).send(body);
    evidence.api.push({ method, url, body, status: res.status, response: res.body });
    return res;
  }
  function net(code, until = '9999-12-31') {
    return db.prepare('SELECT ROUND(COALESCE(SUM(j.debit-j.credit),0),2) AS amount FROM journal_lines j JOIN chart_of_accounts a ON a.id=j.account_id WHERE a.code=? AND j.voided=0 AND j.line_date<=?').get(code, until).amount;
  }
  return { api, net };
}

module.exports = { createIsolatedAuditFixture, startAuditSession };
