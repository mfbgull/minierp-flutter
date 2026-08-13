"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const supertest_1 = __importDefault(require("supertest"));
const bcrypt_1 = __importDefault(require("bcrypt"));
const app_1 = __importDefault(require("../app"));
const database_1 = __importDefault(require("../config/database"));
const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
    throw new Error('TEST_ADMIN_PASSWORD environment variable must be set.');
}
async function getAuthCookie() {
    const res = await (0, supertest_1.default)(app_1.default)
        .post('/api/auth/login')
        .send({ username: 'admin', password: TEST_PASSWORD });
    const cookies = res.headers['set-cookie'];
    if (!cookies)
        return '';
    const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies]).find((c) => c.startsWith('token='));
    return tokenCookie ? tokenCookie.split(';')[0] : '';
}
describe('Preferences Controller (HTTP)', () => {
    let authCookie;
    let adminId;
    beforeAll(async () => {
        authCookie = await getAuthCookie();
        expect(authCookie).not.toBe('');
        // Capture the real admin id from the login response for cleanup.
        const res = await (0, supertest_1.default)(app_1.default).get('/api/auth/me').set('Cookie', authCookie);
        adminId = res.body.data.id;
    });
    afterAll(() => {
        // Tidy: remove any preferences row the tests wrote.
        try {
            database_1.default.prepare('DELETE FROM user_preferences WHERE user_id = ?').run(adminId);
        }
        catch {
            /* ignore cleanup errors */
        }
    });
    it('GET returns server defaults when no row exists', async () => {
        const res = await (0, supertest_1.default)(app_1.default).get('/api/preferences').set('Cookie', authCookie);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body.data).toEqual({ weekStart: 'monday', defaultRange: null, presets: [] });
    });
    it('PUT persists a partial update and returns the saved object', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .put('/api/preferences')
            .set('Cookie', authCookie)
            .send({
            weekStart: 'saturday',
            defaultRange: { from: '2026-08-03', to: '2026-08-09' },
        });
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body.data.weekStart).toBe('saturday');
        expect(res.body.data.defaultRange).toEqual({ from: '2026-08-03', to: '2026-08-09' });
        expect(res.body.data.presets).toEqual([]);
    });
    it('GET returns the persisted values', async () => {
        const res = await (0, supertest_1.default)(app_1.default).get('/api/preferences').set('Cookie', authCookie);
        expect(res.status).toBe(200);
        expect(res.body.data.weekStart).toBe('saturday');
        expect(res.body.data.defaultRange).toEqual({ from: '2026-08-03', to: '2026-08-09' });
    });
    it('PUT persists a full preset set', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .put('/api/preferences')
            .set('Cookie', authCookie)
            .send({ presets: [{ id: 'p1', name: 'Summer', from: '2026-06-01', to: '2026-08-31' }] });
        expect(res.status).toBe(200);
        expect(res.body.data.presets).toHaveLength(1);
        // The partial update must not clobber earlier fields.
        expect(res.body.data.weekStart).toBe('saturday');
    });
    it('PUT rejects an invalid weekStart', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .put('/api/preferences')
            .set('Cookie', authCookie)
            .send({ weekStart: 'friday' });
        expect(res.status).toBe(400);
    });
    it('PUT rejects a malformed defaultRange', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .put('/api/preferences')
            .set('Cookie', authCookie)
            .send({ defaultRange: { from: 'not-a-date', to: '2026-08-09' } });
        expect(res.status).toBe(400);
    });
    it('PUT rejects a reversed defaultRange', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .put('/api/preferences')
            .set('Cookie', authCookie)
            .send({ defaultRange: { from: '2026-08-13', to: '2026-08-01' } });
        expect(res.status).toBe(400);
    });
    it('PUT rejects a reversed preset range', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .put('/api/preferences')
            .set('Cookie', authCookie)
            .send({ presets: [{ id: 'p1', name: 'Bad', from: '2026-08-13', to: '2026-08-01' }] });
        expect(res.status).toBe(400);
    });
    it('PUT rejects duplicate preset ids', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .put('/api/preferences')
            .set('Cookie', authCookie)
            .send({
            presets: [
                { id: 'p1', name: 'A', from: '2026-01-01', to: '2026-01-31' },
                { id: 'p1', name: 'B', from: '2026-02-01', to: '2026-02-28' },
            ],
        });
        expect(res.status).toBe(400);
    });
    it('PUT rejects a preset with an empty id', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .put('/api/preferences')
            .set('Cookie', authCookie)
            .send({ presets: [{ id: '', name: 'A', from: '2026-01-01', to: '2026-01-31' }] });
        expect(res.status).toBe(400);
    });
    it('PUT accepts a single-day defaultRange (from == to)', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .put('/api/preferences')
            .set('Cookie', authCookie)
            .send({ defaultRange: { from: '2026-08-13', to: '2026-08-13' } });
        expect(res.status).toBe(200);
        expect(res.body.data.defaultRange).toEqual({ from: '2026-08-13', to: '2026-08-13' });
    });
    it('PUT clears the defaultRange with an explicit null', async () => {
        const put = await (0, supertest_1.default)(app_1.default)
            .put('/api/preferences')
            .set('Cookie', authCookie)
            .send({ defaultRange: null });
        expect(put.status).toBe(200);
        expect(put.body.data.defaultRange).toBeNull();
    });
    it('GET returns 403 for a user without settings permission', async () => {
        // The seeded 'User' role gets read permissions for every module except
        // 'settings' — exactly the shape that must be denied here.
        const roleRow = database_1.default
            .prepare(`SELECT id FROM roles WHERE role_name = 'User'`)
            .get();
        expect(roleRow).toBeDefined();
        const username = `pref_deny_${Date.now()}`;
        const password = 'deny-pass-123';
        const created = database_1.default
            .prepare(`INSERT INTO users (username, email, password_hash, full_name, role_id, is_active)
         VALUES (?, ?, ?, 'Deny Test', ?, 1)`)
            .run(username, `${username}@test.local`, bcrypt_1.default.hashSync(password, 12), roleRow.id);
        const userId = created.lastInsertRowid;
        try {
            const login = await (0, supertest_1.default)(app_1.default)
                .post('/api/auth/login')
                .send({ username, password });
            const cookies = login.headers['set-cookie'];
            const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies]).find((c) => c.startsWith('token='));
            expect(tokenCookie).toBeDefined();
            const res = await (0, supertest_1.default)(app_1.default)
                .get('/api/preferences')
                .set('Cookie', tokenCookie.split(';')[0]);
            expect(res.status).toBe(403);
        }
        finally {
            // Login wrote an activity_log row referencing the user (FK, no
            // cascade) — clear those first, then the user row itself.
            database_1.default.prepare('DELETE FROM activity_log WHERE user_id = ?').run(userId);
            database_1.default.prepare('DELETE FROM users WHERE id = ?').run(userId);
        }
    });
    it('PUT rejects malformed presets', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .put('/api/preferences')
            .set('Cookie', authCookie)
            .send({ presets: [{ id: 'p1' }] });
        expect(res.status).toBe(400);
    });
    it('PUT rejects a non-object body', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .put('/api/preferences')
            .set('Cookie', authCookie)
            .send([1, 2, 3]);
        expect(res.status).toBe(400);
    });
    it('PUT requires authentication', async () => {
        const res = await (0, supertest_1.default)(app_1.default).put('/api/preferences').send({ weekStart: 'sunday' });
        expect(res.status).toBe(401);
    });
});
//# sourceMappingURL=preferences.test.js.map