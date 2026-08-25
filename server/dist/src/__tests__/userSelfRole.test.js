"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
/**
 * SEC-04 regression tests: self-service edits cannot change own role.
 *
 * The previous guard was inverted — it compared role NAMES and allowed a
 * user to promote themselves to Admin while blocking self-demotion.
 * The fix rejects any self-edit containing role_id, regardless of target.
 */
const supertest_1 = __importDefault(require("supertest"));
const bcrypt_1 = __importDefault(require("bcrypt"));
const app_1 = __importDefault(require("../app"));
const database_1 = __importDefault(require("../config/database"));
const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
    throw new Error('TEST_ADMIN_PASSWORD environment variable must be set.');
}
async function login(username, password) {
    const res = await (0, supertest_1.default)(app_1.default)
        .post('/api/auth/login')
        .send({ username, password });
    const cookies = res.headers['set-cookie'];
    if (!cookies)
        return '';
    const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies])
        .find((c) => c.startsWith('token='));
    return tokenCookie ? tokenCookie.split(';')[0] : '';
}
describe('User self-role guard (SEC-04)', () => {
    let adminCookie;
    let adminId;
    let victimId;
    let victimUsername;
    const victimPassword = 'victim-pass-123';
    beforeAll(async () => {
        adminCookie = await login('admin', TEST_PASSWORD);
        expect(adminCookie).not.toBe('');
        // Resolve the real admin id from the session.
        const me = await (0, supertest_1.default)(app_1.default).get('/api/auth/me').set('Cookie', adminCookie);
        adminId = me.body.data.id;
        // A second active admin-capable user (role_id of the seeded Admin role)
        // so we can prove an admin can still edit ANOTHER user's role.
        const adminRole = database_1.default.prepare(`SELECT id FROM roles WHERE role_name = 'Admin'`).get();
        victimUsername = `sec04_victim_${Date.now()}`;
        const created = database_1.default.prepare(`
      INSERT INTO users (username, email, password_hash, full_name, role, is_active, role_id)
      VALUES (?, ?, ?, 'SEC-04 Victim', 'admin', 1, ?)
    `).run(victimUsername, `${victimUsername}@test.local`, bcrypt_1.default.hashSync(victimPassword, 12), adminRole.id);
        victimId = created.lastInsertRowid;
    });
    afterAll(() => {
        try {
            database_1.default.prepare('DELETE FROM activity_log WHERE entity_type = \'User\' AND (entity_id = ? OR entity_id = ?)').run(adminId, victimId);
            database_1.default.prepare('DELETE FROM users WHERE id = ?').run(victimId);
        }
        catch {
            /* ignore cleanup errors */
        }
    });
    it('rejects self-promotion to Admin with 400 and performs no update', async () => {
        const adminRole = database_1.default.prepare(`SELECT id FROM roles WHERE role_name = 'Admin'`).get();
        const userRole = database_1.default.prepare(`SELECT id FROM roles WHERE role_name = 'User'`).get();
        // Baseline: put the admin on the User role so "promotion" is observable.
        database_1.default.prepare('UPDATE users SET role_id = ? WHERE id = ?').run(userRole.id, adminId);
        const before = database_1.default.prepare('SELECT role_id FROM users WHERE id = ?').get(adminId);
        const res = await (0, supertest_1.default)(app_1.default)
            .put(`/api/users/${adminId}`)
            .set('Cookie', adminCookie)
            .send({ role_id: adminRole.id });
        expect(res.status).toBe(400);
        const after = database_1.default.prepare('SELECT role_id FROM users WHERE id = ?').get(adminId);
        expect(after.role_id).toBe(before.role_id); // unchanged
    });
    it('rejects self-demotion with 400', async () => {
        const userRole = database_1.default.prepare(`SELECT id FROM roles WHERE role_name = 'User'`).get();
        const res = await (0, supertest_1.default)(app_1.default)
            .put(`/api/users/${adminId}`)
            .set('Cookie', adminCookie)
            .send({ role_id: userRole.id });
        expect(res.status).toBe(400);
    });
    it('allows an admin to update another user\'s role', async () => {
        const userRole = database_1.default.prepare(`SELECT id FROM roles WHERE role_name = 'User'`).get();
        const res = await (0, supertest_1.default)(app_1.default)
            .put(`/api/users/${victimId}`)
            .set('Cookie', adminCookie)
            .send({ role_id: userRole.id, full_name: 'SEC-04 Victim Renamed' });
        expect(res.status).toBe(200);
        const after = database_1.default.prepare('SELECT role_id, full_name FROM users WHERE id = ?').get(victimId);
        expect(after.role_id).toBe(userRole.id);
        expect(after.full_name).toBe('SEC-04 Victim Renamed');
    });
});
