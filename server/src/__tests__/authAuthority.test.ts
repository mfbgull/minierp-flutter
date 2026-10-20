import express from 'express';
import { describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { authenticateToken, generateToken, generateRefreshToken, requireAdmin } from '../middleware/auth';
import { AuthRequest } from '../types';

const protectedApp = express();
protectedApp.get('/admin', authenticateToken, requireAdmin, (_req, res) => res.sendStatus(200));
protectedApp.get('/identity', authenticateToken, (req: AuthRequest, res) => res.json(req.user));

let sequence = 0;
function actor() {
  const username = `authority_${++sequence}`;
  const result = db.prepare(`
    INSERT INTO users (username, email, password_hash, full_name, role, is_active)
    VALUES (?, ?, 'unused', ?, 'admin', 1)
  `).run(username, `${username}@example.test`, username);
  const user = { id: Number(result.lastInsertRowid), username, role: 'admin' };
  return { ...user, token: generateToken(user), refreshToken: generateRefreshToken(user) };
}

describe('CODE-002: tokens use current account authority', () => {
  it('allows a current active administrator', async () => {
    const user = actor();
    const response = await request(protectedApp).get('/admin').auth(user.token, { type: 'bearer' });
    expect(response.status).toBe(200);
  });

  it('rejects a bearer token after the account is disabled', async () => {
    const user = actor();
    db.prepare('UPDATE users SET is_active = 0 WHERE id = ?').run(user.id);
    const response = await request(protectedApp).get('/identity').auth(user.token, { type: 'bearer' });
    expect(response.status).toBe(401);
  });

  it('rejects a cookie token after the account is disabled', async () => {
    const user = actor();
    db.prepare('UPDATE users SET is_active = 0 WHERE id = ?').run(user.id);
    const response = await request(app).get('/api/auth/me').set('Cookie', `token=${user.token}`);
    expect(response.status).toBe(401);
  });

  it('rejects an access token after the account is deleted', async () => {
    const user = actor();
    db.prepare('DELETE FROM users WHERE id = ?').run(user.id);
    const response = await request(protectedApp).get('/identity').auth(user.token, { type: 'bearer' });
    expect(response.status).toBe(401);
  });

  it('removes administrator access when the persisted legacy role changes', async () => {
    const user = actor();
    db.prepare("UPDATE users SET role = 'user' WHERE id = ?").run(user.id);
    const response = await request(protectedApp).get('/admin').auth(user.token, { type: 'bearer' });
    expect(response.status).toBe(403);
  });

  it('removes administrator access when the assigned role changes', async () => {
    const user = actor();
    const role = db.prepare("INSERT INTO roles (role_name, is_active) VALUES (?, 1)").run(`limited_${user.id}`);
    db.prepare('UPDATE users SET role_id = ? WHERE id = ?').run(role.lastInsertRowid, user.id);
    const response = await request(protectedApp).get('/admin').auth(user.token, { type: 'bearer' });
    expect(response.status).toBe(403);
  });

  it('uses the current username instead of stale token claims', async () => {
    const user = actor();
    db.prepare('UPDATE users SET username = ? WHERE id = ?').run(`${user.username}_updated`, user.id);
    const response = await request(protectedApp).get('/identity').auth(user.token, { type: 'bearer' });
    expect(response.status).toBe(200);
    expect(response.body.username).toBe(`${user.username}_updated`);
  });

  it('does not grant administrator authority to a custom role named admin', async () => {
    const user = actor();
    const role = db.prepare("INSERT INTO roles (role_name, is_system_role, is_active) VALUES ('admin', 0, 1)").run();
    db.prepare('UPDATE users SET role_id = ? WHERE id = ?').run(role.lastInsertRowid, user.id);

    const response = await request(protectedApp).get('/admin').auth(user.token, { type: 'bearer' });

    expect(response.status).toBe(403);
  });

  it('reports the effective non-admin role and permissions after a role assignment changes', async () => {
    const user = actor();
    const role = db.prepare("INSERT INTO roles (role_name, is_active) VALUES (?, 1)").run(`profile_${user.id}`);
    db.prepare('UPDATE users SET role_id = ? WHERE id = ?').run(role.lastInsertRowid, user.id);

    const response = await request(app).get('/api/auth/me').auth(user.token, { type: 'bearer' });

    expect(response.status).toBe(200);
    expect(response.body.data.role).toBe('user');
    expect(response.body.data.permissions).toEqual([]);
  });

  it('reports the system Admin role even if the legacy role string disagrees', async () => {
    const user = actor();
    const role = db.prepare<[], { id: number }>("SELECT id FROM roles WHERE role_name = 'Admin' AND is_system_role = 1").get();
    if (!role) throw new Error('Missing fixture Admin role');
    db.prepare("UPDATE users SET role = 'user', role_id = ? WHERE id = ?").run(role.id, user.id);

    const response = await request(app).get('/api/auth/me').auth(user.token, { type: 'bearer' });

    expect(response.status).toBe(200);
    expect(response.body.data.role).toBe('admin');
    expect(response.body.data.permissions.length).toBeGreaterThan(0);
  });

  it('rejects a refresh token presented as an access token', async () => {
    const user = actor();
    const response = await request(protectedApp).get('/admin').auth(user.refreshToken, { type: 'bearer' });
    expect(response.status).toBe(401);
  });

  it.each(['disabled', 'deleted'])('rejects refresh for a %s account', async (state) => {
    const user = actor();
    if (state === 'disabled') db.prepare('UPDATE users SET is_active = 0 WHERE id = ?').run(user.id);
    else db.prepare('DELETE FROM users WHERE id = ?').run(user.id);
    const response = await request(app).post('/api/auth/refresh').send({ refreshToken: user.refreshToken });
    expect(response.status).toBe(401);
    expect(response.body.data?.token).toBeUndefined();
  });

  it('refreshes with the current assigned role rather than the old admin claim', async () => {
    const user = actor();
    const role = db.prepare("INSERT INTO roles (role_name, is_active) VALUES (?, 1)").run(`refreshed_${user.id}`);
    db.prepare('UPDATE users SET role_id = ? WHERE id = ?').run(role.lastInsertRowid, user.id);
    const response = await request(app).post('/api/auth/refresh').send({ refreshToken: user.refreshToken });
    expect(response.status).toBe(200);
    const claims = JSON.parse(Buffer.from(response.body.data.token.split('.')[1], 'base64url').toString());
    expect(claims.role).toBe('user');
  });
});
