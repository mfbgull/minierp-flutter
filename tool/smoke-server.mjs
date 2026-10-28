#!/usr/bin/env node
/**
 * Boot a staged server payload with its bundled Node runtime and wait for
 * /health. Used before a release artifact is uploaded so an ABI mismatch or a
 * missing migration fails the build instead of the installer.
 *
 *   node tool/smoke-server.mjs --server build/server-stage
 *
 * Options:
 *   --server <dir>  staged server directory (dist/, node_modules/, runtime/)
 *   --timeout <ms>  boot timeout, default 120000
 *   --keep          keep the temporary data directory (for debugging)
 */
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

function parseArgs(argv) {
  const args = { server: null, timeout: 120_000, keep: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--server') args.server = path.resolve(argv[++i]);
    else if (arg === '--timeout') args.timeout = Number(argv[++i]);
    else if (arg === '--keep') args.keep = true;
    else throw new Error(`Unknown argument: ${arg}`);
  }
  if (!args.server) throw new Error('--server is required');
  return args;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForHealth(portFile, timeoutMs, onLog) {
  const deadline = Date.now() + timeoutMs;
  let port = null;

  while (Date.now() < deadline) {
    if (!port && fs.existsSync(portFile)) {
      const raw = fs.readFileSync(portFile, 'utf8').trim();
      const parsed = Number(raw);
      if (Number.isInteger(parsed) && parsed > 0) {
        port = parsed;
        onLog(`[smoke] server port ${port}`);
      }
    }
    if (port) {
      try {
        const response = await fetch(`http://127.0.0.1:${port}/health`, {
          signal: AbortSignal.timeout(3000),
        });
        if (response.ok) {
          const body = await response.json();
          if (body.status === 'ok' || body.status === 'degraded') {
            return { port, body };
          }
          onLog(`[smoke] health not ready: ${body.status}`);
        }
      } catch {
        // Not listening yet.
      }
    }
    await sleep(250);
  }
  throw new Error(`server did not become healthy within ${timeoutMs} ms`);
}

function stop(child) {
  return new Promise((resolve) => {
    if (child.exitCode !== null) {
      resolve();
      return;
    }
    const timer = setTimeout(() => {
      try { child.kill('SIGKILL'); } catch { /* already gone */ }
      resolve();
    }, 5000);
    child.once('exit', () => {
      clearTimeout(timer);
      resolve();
    });
    try { child.kill('SIGTERM'); } catch { /* already gone */ }
  });
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const serverDir = args.server;
  const entry = path.join(serverDir, 'dist', 'server.js');
  if (!fs.existsSync(entry)) throw new Error(`missing ${entry}`);

  const binary = path.join(
    serverDir,
    'runtime',
    process.platform === 'win32' ? 'node.exe' : 'node',
  );
  if (!fs.existsSync(binary)) throw new Error(`missing bundled runtime: ${binary}`);

  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'minierp-smoke-'));
  for (const dir of ['server', 'database', 'backups', 'uploads', 'logs']) {
    fs.mkdirSync(path.join(dataDir, dir), { recursive: true });
  }

  const portFile = path.join(dataDir, 'server.port');
  const pidFile = path.join(dataDir, 'server.pid');
  const env = {
    ...process.env,
    NODE_ENV: 'production',
    PORT: '0',
    HOST: '127.0.0.1',
    JWT_SECRET: 'smoke-only-jwt-secret-0123456789abcdef',
    DEFAULT_ADMIN_PASSWORD: 'Smoke-Test-Password-2026!',
    ALLOWED_ORIGINS: 'http://127.0.0.1',
    DATABASE_PATH: path.join(dataDir, 'database'),
    BACKUP_DIR: path.join(dataDir, 'backups'),
    UPLOADS_DIR: path.join(dataDir, 'uploads'),
    LOG_DIR: path.join(dataDir, 'logs'),
    SERVE_CLIENT: 'false',
    PORT_FILE: portFile,
    PID_FILE: pidFile,
  };
  delete env.MINIERP_PARENT_PID;

  const output = [];
  const onLog = (line) => {
    output.push(line);
    if (output.length > 200) output.shift();
  };

  console.log(`[smoke] starting ${binary} ${entry}`);
  const child = spawn(binary, [entry], {
    cwd: path.join(dataDir, 'server'),
    env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  child.stdout.on('data', (chunk) => onLog(String(chunk)));
  child.stderr.on('data', (chunk) => onLog(String(chunk)));

  let failure = null;
  try {
    const health = await waitForHealth(portFile, args.timeout, onLog);
    if (!fs.existsSync(path.join(dataDir, 'database', 'erp.db'))) {
      throw new Error('database/erp.db was not created');
    }
    console.log(`[smoke] healthy: ${JSON.stringify(health.body).slice(0, 160)}`);
  } catch (error) {
    failure = error;
  } finally {
    await stop(child);
  }

  if (failure) {
    console.error(`[smoke] failed: ${failure.message}`);
    console.error('[smoke] last server output:');
    console.error(output.join(''));
    console.error(`[smoke] data dir kept at ${dataDir}`);
    process.exit(1);
  }

  if (!args.keep) fs.rmSync(dataDir, { recursive: true, force: true });
  console.log('[smoke] ok');
}

main().catch((error) => {
  console.error(`[smoke] failed: ${error instanceof Error ? error.message : error}`);
  process.exit(1);
});
