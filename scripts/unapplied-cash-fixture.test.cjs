const { test } = require('node:test');
const assert = require('node:assert/strict');
const { validateEnvironment } = require('../server/scripts/fixtures/unapplied-cash-ui.cjs');

test('fixture refuses a caller-selected database or production environment', () => {
  assert.throws(() => validateEnvironment({ DATABASE_PATH: '/tmp/not-owned' }));
  assert.throws(() => validateEnvironment({ NODE_ENV: 'production' }));
  assert.doesNotThrow(() => validateEnvironment({}));
});
