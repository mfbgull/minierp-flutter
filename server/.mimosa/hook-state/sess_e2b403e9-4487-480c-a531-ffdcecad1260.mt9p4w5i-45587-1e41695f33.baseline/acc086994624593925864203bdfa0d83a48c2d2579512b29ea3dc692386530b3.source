/**
 * SEC-02 verification: with the committed server/.env (NODE_ENV=production),
 * the login rate limiter is active — repeated failed logins return 429.
 *
 * The limiter reads NODE_ENV at module load, so this suite runs in a child
 * process with NODE_ENV=production forced before the app is imported
 * (jest sets it to 'test' in-process).
 */
import { spawnSync } from 'child_process';
import path from 'path';
import fs from 'fs';
import os from 'os';

const SERVER_ROOT = path.join(__dirname, '..', '..');

describe('Rate limiters active under committed config (SEC-02)', () => {
  it('committed server/.env sets NODE_ENV to a production-safe value', () => {
    const envFile = fs.readFileSync(path.join(SERVER_ROOT, '.env'), 'utf8');
    const match = envFile.match(/^NODE_ENV=(.*)$/m);
    expect(match).not.toBeNull();
    expect(match![1].trim()).toBe('production');
  });

  it('returns 429 after repeated failed logins when NODE_ENV=production', () => {
    // Isolated temp DB so this never touches developer data.
    const dbDir = fs.mkdtempSync(path.join(os.tmpdir(), 'sec02-rl-'));
    const script = `
      process.env.NODE_ENV = 'production';
      process.env.DATABASE_PATH = ${JSON.stringify(dbDir)};
      process.env.DEFAULT_ADMIN_PASSWORD = 'x-sec02-default';
      require('ts-node').register({ transpileOnly: true, project: './tsconfig.json' });
      const request = require('supertest');
      const app = require('./src/app').default;
      let got429 = false;
      let lastStatus = 0;
      (async () => {
        for (let i = 0; i < 12; i++) {
          const res = await request(app).post('/api/auth/login')
            .send({ username: 'nobody-sec02', password: 'wrong-password' });
          lastStatus = res.status;
          if (res.status === 429) { got429 = true; break; }
        }
        console.log('RESULT:' + JSON.stringify({ got429, lastStatus }));
        process.exit(0);
      })().catch((e) => { console.error(e); process.exit(1); });
    `;
    try {
      const res = spawnSync(process.execPath, ['-e', script], {
        cwd: SERVER_ROOT,
        encoding: 'utf8',
        timeout: 120_000,
        env: {
          ...process.env,
          JWT_SECRET: 'sec02-test-secret',
          ALLOWED_ORIGINS: 'http://localhost:3011',
        },
      });
      const out = `${res.stdout || ''}`;
      const resultMatch = out.match(/RESULT:(\{.*\})/);
      expect(resultMatch).not.toBeNull();
      const parsed = JSON.parse(resultMatch![1]);
      // Under production NODE_ENV the authLimiter allows 5 attempts / 15 min.
      expect(parsed.got429).toBe(true);
      expect(parsed.lastStatus).toBe(429);
    } finally {
      try { fs.rmSync(dbDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  }, 150_000);
});
