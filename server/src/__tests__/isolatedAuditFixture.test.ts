import { spawnSync } from 'node:child_process';
import { expect, it } from '@jest/globals';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

it('confines every audit SQLite constructor to its fresh fixture before opening files', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'audit-fixture-smoke-'));
  const root = path.resolve(__dirname, '../../..');
  try {
    const child = spawnSync(process.execPath, ['-e', `
      const assert = require('node:assert/strict');
      const fs = require('node:fs');
      const path = require('node:path');
      const root = process.argv[1];
      const directory = process.argv[2];
      const { createIsolatedAuditFixture, startAuditSession } = require(path.join(root, 'accounting-audit/tests/lib/isolated-fixture.cjs'));
      const { run, database, db, evidence } = createIsolatedAuditFixture(path.join(directory, 'owned-run-'));
      assert.deepEqual(evidence, {
        run, guard: 'Every SQLite constructor restricted to newly created run directory', api: [], scenarios: [],
      });
      const Sqlite = require(path.join(root, 'server/node_modules/better-sqlite3'));
      assert(run.startsWith(path.join(directory, 'owned-run-')));
      assert.equal(process.env.NODE_ENV, 'test');
      assert.equal(process.env.DATABASE_PATH, run);
      assert.equal(process.env.LOG_DIR, path.join(run, 'logs'));
      assert.equal(process.env.JWT_SECRET, 'backend-audit-fixture-secret-only-2026');
      assert.equal(process.env.DEFAULT_ADMIN_PASSWORD, 'Backend-audit-fixture-password-2026!');
      assert.equal(typeof database.applyPendingMigrations, 'function');
      assert.equal(db, database.default);
      const inside = new Sqlite(path.join(run, 'allowed.db'));
      assert.deepEqual(inside.prepare('SELECT 42 AS value').get(), { value: 42 });
      inside.close();
      for (const outside of [path.join(directory, 'outside.db'), run + '-sibling.db', path.join(run, '..', 'traversal.db')]) {
        assert.throws(() => new Sqlite(outside), /Refusing DB outside disposable fixture/);
        assert.equal(fs.existsSync(outside), false);
      }
      assert.throws(() => new Sqlite(':memory:'), /Refusing DB outside disposable fixture/);
      let cleanup;
      async function verifySession() {
        const { api, net } = await startAuditSession({ database, db }, evidence, value => { cleanup = value; });
        const res = await api('get', '/api/inventory/items');
        assert.equal(res.status, 200);
        assert.equal(evidence.api.length, 1);
        assert.equal(evidence.api[0].url, '/api/inventory/items');
        assert.deepEqual(evidence.api[0].response, res.body);
        assert.equal(net('1000'), 0);
        assert.equal(net('1000', '1900-01-01'), 0);
        const afterBoot = path.join(directory, 'after-boot.db');
        assert.throws(() => new Sqlite(afterBoot), /Refusing DB outside disposable fixture/);
        assert.equal(fs.existsSync(afterBoot), false);
        console.log('AUDIT_FIXTURE_CONFINEMENT_PASS');
      }
      verifySession().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
        db.close();
        if (cleanup) cleanup();
      });
    `, root, directory], { encoding: 'utf8', timeout: 60000 });
    expect(child.error).toBeUndefined();
    expect({ status: child.status, stderr: child.stderr }).toEqual({ status: 0, stderr: '' });
    expect(child.stdout).toContain('AUDIT_FIXTURE_CONFINEMENT_PASS');
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
