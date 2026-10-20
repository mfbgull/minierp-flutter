import { afterEach, beforeAll, beforeEach, describe, expect, it } from '@jest/globals';
import bcrypt from 'bcrypt';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { generateToken } from '../middleware/auth';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

const currentPassword = 'Current-password-123';
let cookie: string;
let userId: number;
let token: string;
let roleId: number;
beforeAll(async () => {
  cookie = await getAuthCookie();
  const role = db.prepare<[], { id: number }>("SELECT id FROM roles WHERE role_name='User'").get();
  if (!role) throw new Error('Missing fixture User role');
  roleId = role.id;
  const user = db.prepare(`INSERT INTO users (username,email,password_hash,full_name,role,role_id)
    VALUES ('password-policy','password-policy@example.test',?,'Password policy','user',?)`)
    .run(await bcrypt.hash(currentPassword, 4), roleId);
  userId = Number(user.lastInsertRowid);
  token = generateToken({ id: userId, username: 'password-policy', role: 'user' });
});
beforeEach(() => { db.exec('SAVEPOINT password_policy_case'); });
afterEach(() => { db.exec('ROLLBACK TO password_policy_case; RELEASE password_policy_case'); });

function storedHash(): unknown {
  return db.prepare('SELECT password_hash FROM users WHERE id=?').get(userId);
}

describe('CODE-003: password writes enforce one bounded policy', () => {
  it.each(['short123', 'x'.repeat(73), '😀'.repeat(20)])('rejects an invalid new-user password (%s)', async (password) => {
    const response = await request(app).post('/api/users').set('Cookie', cookie).send({
      username: 'rejected-password', email: 'rejected@example.test', password,
      full_name: 'Rejected password', role_id: roleId,
    });

    expect(response.status).toBe(400);
    expect(db.prepare("SELECT id FROM users WHERE username='rejected-password'").get()).toBeUndefined();
  });

  it.each(['short123', 'x'.repeat(73), '😀'.repeat(20)])('rejects an invalid password reset (%s)', async (newPassword) => {
    const before = storedHash();
    const response = await request(app).put(`/api/users/${userId}/reset-password`)
      .set('Cookie', cookie).send({ newPassword });

    expect(response.status).toBe(400);
    expect(storedHash()).toEqual(before);
  });

  it.each(['short123', 'x'.repeat(73), '😀'.repeat(20)])('rejects an invalid self-service password change (%s)', async (newPassword) => {
    const before = storedHash();
    const response = await request(app).post('/api/auth/change-password').auth(token, { type: 'bearer' })
      .send({ currentPassword, newPassword });

    expect(response.status).toBe(400);
    expect(storedHash()).toEqual(before);
  });

  it('accepts a twelve-character password without imposing composition rules', async () => {
    const response = await request(app).post('/api/auth/change-password').auth(token, { type: 'bearer' })
      .send({ currentPassword, newPassword: 'twelvechars!' });

    expect(response.status).toBe(200);
    const login = await request(app).post('/api/auth/login').send({ username: 'password-policy', password: 'twelvechars!' });
    expect(login.status).toBe(200);
  });
});
