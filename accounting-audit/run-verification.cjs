'use strict';

// Audit artifacts only. This runner never imports the database or application.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawn, spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const evidence = path.join(__dirname, 'evidence');
fs.mkdirSync(evidence, { recursive: true });
const ignored = new Set(['.git', 'node_modules', 'build', 'dist', '.dart_tool', '.tmp-test', '.omo', 'accounting-audit', '.codebase-memory']);
const protectedRoots = ['server/src', 'server/scripts', 'server/docs', 'lib', 'test', 'integration_test', 'scripts', 'docs', '.github'];
function walk(relative) {
  const absolute = path.join(root, relative);
  if (!fs.existsSync(absolute)) return [];
  return fs.readdirSync(absolute, { withFileTypes: true }).flatMap(entry => {
    if (ignored.has(entry.name) || entry.isSymbolicLink()) return [];
    const file = path.posix.join(relative, entry.name);
    return entry.isDirectory() ? walk(file) : [file];
  });
}
function hashes() {
  return Object.fromEntries(protectedRoots.flatMap(walk).sort().map(file => [file,
    crypto.createHash('sha256').update(fs.readFileSync(path.join(root, file))).digest('hex')]));
}
const mode = process.argv[2];
if (mode === 'snapshot') {
  const data = { capturedAt: new Date().toISOString(), revision: spawnSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).stdout.trim(), sourceHashes: hashes() };
  const dest = path.join(evidence, 'source-baseline.json');
  if (fs.existsSync(dest)) throw new Error('Refusing to overwrite original baseline');
  fs.writeFileSync(dest, JSON.stringify(data, null, 2));
  const inventory = protectedRoots.flatMap(walk).sort();
  fs.writeFileSync(path.join(evidence, 'repository-file-inventory.txt'), inventory.join('\n') + '\n');
  console.log(JSON.stringify({ revision: data.revision, protectedFiles: inventory.length, baseline: path.relative(root, dest) }));
} else if (mode === 'compare') {
  const before = JSON.parse(fs.readFileSync(path.join(evidence, 'source-baseline.json'), 'utf8'));
  const now = hashes();
  const changed = Object.keys(before.sourceHashes).filter(file => before.sourceHashes[file] !== now[file]);
  const added = Object.keys(now).filter(file => !(file in before.sourceHashes));
  const result = { checkedAt: new Date().toISOString(), changed, added, unchanged: changed.length === 0 && added.length === 0 };
  fs.writeFileSync(path.join(evidence, 'source-preservation.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result));
  if (!result.unchanged) process.exitCode = 1;
} else if (mode === 'checks') {
  const jobs = [
    { name: 'quick', command: 'bash', args: ['scripts/check.sh', '--quick'], cwd: root },
    { name: 'server-full', command: 'npm', args: ['test', '--', '--runInBand', '--json', '--outputFile=' + path.join(evidence, 'server-full-results.json')], cwd: path.join(root, 'server') },
    { name: 'flutter-full', command: 'flutter', args: ['test', '--reporter', 'json'], cwd: root },
  ];
  const manifest = [];
  const manifestPath = path.join(evidence, 'verification-runs.json');
  (async () => {
    for (const job of jobs) {
      const log = path.join(evidence, job.name + '.log');
      const fd = fs.openSync(log, 'w');
      const startedAt = new Date().toISOString();
      console.log('START ' + job.name + ' ' + startedAt);
      const child = spawn(job.command, job.args, { cwd: job.cwd, env: { ...process.env, NODE_ENV: 'test', TEST_TMPDIR: path.join(root, 'server/.tmp-test/accounting-audit-full') }, stdio: ['ignore', fd, fd] });
      const result = await new Promise(resolve => {
        child.once('error', error => resolve({ exitCode: null, error: error.message }));
        child.once('close', (exitCode, signal) => resolve({ exitCode, signal }));
      });
      fs.closeSync(fd);
      manifest.push({ name: job.name, command: [job.command, ...job.args], cwd: path.relative(root, job.cwd) || '.', startedAt, endedAt: new Date().toISOString(), log: path.relative(root, log), ...result });
      fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
      console.log('END ' + job.name + ' ' + JSON.stringify(result));
    }
    process.exitCode = manifest.every(run => run.exitCode === 0) ? 0 : 1;
  })().catch(error => { console.error(error.message); process.exitCode = 1; });
} else {
  throw new Error('Usage: node accounting-audit/run-verification.cjs snapshot|compare|checks');
}
