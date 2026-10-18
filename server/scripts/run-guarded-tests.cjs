const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const server = path.resolve(__dirname, '..');
const canonical = path.join(server, 'database/erp.db');
const files = [canonical, `${canonical}-wal`, `${canonical}-shm`];
const baseline = '27e5cc340bb5a43a1d4974f3b206ccfd05919e13a75bcefa6e16b13e5bd7bc97';

function fingerprint(filename) {
  return fs.existsSync(filename)
    ? crypto.createHash('sha256').update(fs.readFileSync(filename)).digest('hex')
    : null;
}

const before = files.map(fingerprint);
if (before[0] !== null && before[0] !== baseline) {
  throw new Error('Canonical database baseline changed; tests were not started');
}

try {
  const child = spawnSync(process.execPath, [require.resolve('jest/bin/jest'), ...process.argv.slice(2)], {
    cwd: server,
    stdio: 'inherit',
  });
  if (child.error) throw child.error;
  process.exitCode = child.status ?? 1;
} finally {
  const after = files.map(fingerprint);
  const changed = files
    .map((filename, index) => ({ filename, before: before[index], after: after[index] }))
    .filter(({ before: previous, after: current }) => previous !== current);
  if (changed.length > 0) {
    console.error('Canonical database or WAL/SHM changed during test execution:');
    for (const entry of changed) {
      console.error(`${entry.filename}: ${entry.before ?? '<missing>'} -> ${entry.after ?? '<missing>'}`);
    }
    process.exitCode = 1;
  }
}
