import request from 'supertest';
import app from './src/app';
import db from './src/config/database';
import { flushLogs } from './src/services/activityLogger';

(async () => {
  const login = await request(app).post('/api/auth/login')
    .send({ username: 'admin', password: 'test-admin-password-secure-2026' });
  const cookies = login.headers['set-cookie'];
  const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies]).find((c: string) => c.startsWith('token='));
  const authCookie = tokenCookie!.split(';')[0];

  // wait 1.5s for the LOGIN row to flush
  await new Promise(r => setTimeout(r, 1500));
  console.log('after login flush:', db.prepare("SELECT action FROM activity_log ORDER BY id DESC LIMIT 3").all());
  flushLogs();
})();
