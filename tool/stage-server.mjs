#!/usr/bin/env node
/**
 * Build a self-contained server payload for a release artifact.
 *
 *   node tool/stage-server.mjs --dist server/dist --out build/server-stage
 *
 * The payload contains the compiled server, production node_modules built for
 * the current OS, and a Node runtime whose ABI matches them. Run this on each
 * target OS (Linux, Windows, macOS x64/arm64); dist is platform-independent,
 * but better-sqlite3 and bcrypt are not.
 *
 * Options:
 *   --dist <dir>           compiled server directory (default: server/dist)
 *   --out <dir>            output payload directory (required)
 *   --node-version <x.y.z> runtime version (default: the running Node)
 *   --skip-npm             reuse node_modules already present in --out
 *   --skip-runtime         do not download a Node runtime
 */
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const TOOL_DIR = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(TOOL_DIR, '..');

function parseArgs(argv) {
  const args = {
    dist: path.join(REPO_ROOT, 'server', 'dist'),
    out: null,
    nodeVersion: process.versions.node,
    skipNpm: false,
    skipRuntime: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--dist') args.dist = path.resolve(argv[++i]);
    else if (arg === '--out') args.out = path.resolve(argv[++i]);
    else if (arg === '--node-version') args.nodeVersion = argv[++i];
    else if (arg === '--skip-npm') args.skipNpm = true;
    else if (arg === '--skip-runtime') args.skipRuntime = true;
    else if (arg === '--help' || arg === '-h') {
      console.log(fs.readFileSync(fileURLToPath(import.meta.url), 'utf8').split('*/')[0]);
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }
  if (!args.out) throw new Error('--out is required');
  return args;
}

function rmrf(target) {
  fs.rmSync(target, { recursive: true, force: true });
}

function copyDist(distDir, outDir) {
  const entry = path.join(distDir, 'server.js');
  if (!fs.existsSync(entry)) {
    throw new Error(`compiled entry missing: ${entry} (run "npm run build" in server/)`);
  }

  const dest = path.join(outDir, 'dist');
  fs.cpSync(distDir, dest, {
    recursive: true,
    filter: (src) => {
      const rel = path.relative(distDir, src);
      if (!rel) return true;
      // Runtime reads dist/src/migrations. The top-level copy is redundant.
      if (rel === 'migrations' || rel.startsWith(`migrations${path.sep}`)) return false;
      if (rel === path.join('src', '__tests__') ||
          rel.startsWith(`${path.join('src', '__tests__')}${path.sep}`)) return false;
      if (rel.endsWith('.map') || rel.endsWith('.ts')) return false;
      return true;
    },
  });

  if (!fs.existsSync(path.join(dest, 'src', 'migrations'))) {
    throw new Error('dist/src/migrations is missing; the server cannot migrate on boot');
  }
}

function copyPackageFiles(outDir) {
  const packageJson = path.join(REPO_ROOT, 'server', 'package.json');
  const lock = path.join(REPO_ROOT, 'server', 'package-lock.json');
  fs.copyFileSync(packageJson, path.join(outDir, 'package.json'));
  fs.copyFileSync(lock, path.join(outDir, 'package-lock.json'));
}

function installProductionDeps(outDir) {
  const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm';
  console.log('[stage] npm ci --omit=dev');
  execFileSync(npm, ['ci', '--omit=dev', '--no-audit', '--no-fund'], {
    cwd: outDir,
    stdio: 'inherit',
    shell: process.platform === 'win32',
    env: process.env,
  });
}

export function pruneBcryptPrebuilds(outDir) {
  const require = createRequire(path.join(outDir, 'package.json'));
  const bcryptDir = path.dirname(require.resolve('bcrypt/package.json'));
  const bcryptRequire = createRequire(path.join(bcryptDir, 'package.json'));
  const selected = bcryptRequire('node-gyp-build').path(bcryptDir);
  // npm ships every platform/libc variant. linuxdeploy scans even unused ELFs,
  // so retain only the addon bcrypt's loader would actually use on this target.
  const prebuilds = path.join(bcryptDir, 'prebuilds');
  if (!fs.existsSync(prebuilds)) return;
  for (const target of fs.readdirSync(prebuilds)) {
    const targetDir = path.join(prebuilds, target);
    if (targetDir !== path.dirname(selected)) {
      rmrf(targetDir);
      continue;
    }
    for (const file of fs.readdirSync(targetDir)) {
      const binary = path.join(targetDir, file);
      if (binary !== selected) rmrf(binary);
    }
  }
}

function runtimeArtifact(version, platform, arch) {
  if (platform === 'linux') return `node-v${version}-linux-${arch}.tar.xz`;
  if (platform === 'darwin') return `node-v${version}-darwin-${arch}.tar.gz`;
  if (platform === 'win32') return `node-v${version}-win-${arch}.zip`;
  throw new Error(`Unsupported platform: ${platform}`);
}

async function download(url, destination) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`download failed (${response.status}): ${url}`);
  const buffer = Buffer.from(await response.arrayBuffer());
  fs.writeFileSync(destination, buffer);
  return buffer;
}

async function fetchExpectedSha(version, artifact) {
  const response = await fetch(`https://nodejs.org/dist/v${version}/SHASUMS256.txt`);
  if (!response.ok) throw new Error(`cannot fetch SHASUMS256.txt (${response.status})`);
  const text = await response.text();
  for (const line of text.split('\n')) {
    const [sha, name] = line.trim().split(/\s+/);
    if (name === artifact) return sha;
  }
  throw new Error(`no checksum for ${artifact}`);
}

function extractRuntime(archive, workDir) {
  // Windows 10+ and every CI runner ship bsdtar, which also reads .zip.
  execFileSync('tar', ['-xf', archive, '-C', workDir], { stdio: 'inherit' });
  return fs.readdirSync(workDir).find((name) => name.startsWith('node-v'));
}

async function stageRuntime(outDir, version) {
  const platform = process.platform;
  const arch = process.arch;
  const artifact = runtimeArtifact(version, platform, arch);
  const workDir = fs.mkdtempSync(path.join(os.tmpdir(), 'minierp-runtime-'));
  const archive = path.join(workDir, artifact);

  try {
    console.log(`[stage] downloading ${artifact}`);
    const buffer = await download(`https://nodejs.org/dist/v${version}/${artifact}`, archive);
    const expected = await fetchExpectedSha(version, artifact);
    const actual = createHash('sha256').update(buffer).digest('hex');
    if (actual !== expected) {
      throw new Error(`checksum mismatch for ${artifact}: expected ${expected}, got ${actual}`);
    }

    const extractedRoot = extractRuntime(archive, workDir);
    if (!extractedRoot) throw new Error(`could not find extracted Node in ${workDir}`);

    const runtimeDir = path.join(outDir, 'runtime');
    fs.mkdirSync(runtimeDir, { recursive: true });
    const binaryName = platform === 'win32' ? 'node.exe' : 'node';
    const binarySource = platform === 'win32'
      ? path.join(workDir, extractedRoot, 'node.exe')
      : path.join(workDir, extractedRoot, 'bin', 'node');

    fs.copyFileSync(binarySource, path.join(runtimeDir, binaryName));
    if (platform !== 'win32') fs.chmodSync(path.join(runtimeDir, binaryName), 0o755);

    const license = path.join(workDir, extractedRoot, 'LICENSE');
    if (fs.existsSync(license)) fs.copyFileSync(license, path.join(runtimeDir, 'LICENSE'));

    console.log(`[stage] runtime ${version} (${platform}-${arch}) staged`);
  } finally {
    rmrf(workDir);
  }
}

function smokeNativeModules(outDir) {
  const binary = path.join(outDir, 'runtime', process.platform === 'win32' ? 'node.exe' : 'node');
  const sqlite = path.join(outDir, 'node_modules', 'better-sqlite3');
  const bcrypt = path.join(outDir, 'node_modules', 'bcrypt');
  const script = `
    const Database = require(process.argv[1]);
    const db = new Database(':memory:');
    db.exec('CREATE TABLE t(x)');
    db.close();
    require(process.argv[2]);
    console.log('ABI OK node=' + process.version + ' modules=' + process.versions.modules);
  `;
  console.log('[stage] verifying bundled runtime + native modules');
  execFileSync(binary, ['-e', script, sqlite, bcrypt], { stdio: 'inherit' });
}

function directorySize(dir) {
  let total = 0;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    total += entry.isDirectory() ? directorySize(full) : fs.statSync(full).size;
  }
  return total;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const outDir = args.out;

  rmrf(outDir);
  fs.mkdirSync(outDir, { recursive: true });

  copyDist(path.resolve(args.dist), outDir);
  copyPackageFiles(outDir);
  // Runtime data directories (database, uploads, logs) are deliberately NOT
  // created here: the client always launches the server with
  // DATABASE_PATH/UPLOADS_DIR/JWT state in the per-user data directory
  // (BackendPaths.resolveDataDir), so payload fallback dirs would be inert —
  // and shipped empty shells invited readers to think the package carried
  // data (docs/bugs.md BUG-009).

  if (!args.skipNpm) installProductionDeps(outDir);
  if (!args.skipNpm) pruneBcryptPrebuilds(outDir);
  if (!args.skipRuntime) await stageRuntime(outDir, args.nodeVersion);
  if (!args.skipRuntime) smokeNativeModules(outDir);

  const sizeMb = (directorySize(outDir) / 1024 / 1024).toFixed(1);
  console.log(`[stage] ready: ${outDir} (${sizeMb} MB, node ${args.nodeVersion})`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(`[stage] failed: ${error instanceof Error ? error.message : error}`);
    process.exit(1);
  });
}
