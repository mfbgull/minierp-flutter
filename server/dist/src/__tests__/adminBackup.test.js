"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
/**
 * Admin backup HTTP API (routes/adminBackup.ts).
 *
 * Covers the manual trigger (activity-trail attribution), listing,
 * download streaming, deletion + BACKUP_DELETE trail row, traversal-name
 * rejection and the permission gate for non-admin roles.
 */
const supertest_1 = __importDefault(require("supertest"));
const bcrypt_1 = __importDefault(require("bcrypt"));
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const app_1 = __importDefault(require("../app"));
const database_1 = __importDefault(require("../config/database"));
jest.setTimeout(30000);
const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD)
    throw new Error('TEST_ADMIN_PASSWORD must be set');
// DATABASE_PATH is the database directory; backupService nests backups/ in it.
const BACKUP_DIR = path_1.default.join(process.env.DATABASE_PATH, 'backups');
async function getAuthCookie(username = 'admin', password = TEST_PASSWORD) {
    const res = await (0, supertest_1.default)(app_1.default)
        .post('/api/auth/login')
        .send({ username, password });
    const cookies = res.headers['set-cookie'];
    if (!cookies)
        return '';
    const cookieList = Array.isArray(cookies) ? cookies : [cookies];
    const tokenCookie = cookieList.find((c) => c.startsWith('token='));
    return tokenCookie ? tokenCookie.split(';')[0] : '';
}
describe('admin backup endpoints', () => {
    let authCookie;
    let fileName = '';
    beforeAll(async () => {
        authCookie = await getAuthCookie();
        expect(authCookie).not.toBe('');
    });
    it('rejects unauthenticated access', async () => {
        expect((await (0, supertest_1.default)(app_1.default).get('/api/admin/backup')).status).toBe(401);
        expect((await (0, supertest_1.default)(app_1.default).post('/api/admin/backup')).status).toBe(401);
    });
    it('POST creates a manual backup attributed to the caller', async () => {
        const adminId = database_1.default.prepare(`SELECT id FROM users WHERE username = 'admin'`).get().id;
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/admin/backup')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        fileName = res.body.data.fileName;
        expect(fileName).toMatch(/^erp-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}\.db$/);
        expect(fs_1.default.existsSync(path_1.default.join(BACKUP_DIR, fileName))).toBe(true);
        // Staleness marker for the nightly scheduler must be maintained.
        expect(fs_1.default.existsSync(path_1.default.join(BACKUP_DIR, '.last_backup'))).toBe(true);
        const row = database_1.default.prepare(`SELECT user_id, description FROM activity_log
       WHERE action = 'BACKUP_CREATE' AND description LIKE 'Manual backup %'
       ORDER BY id DESC LIMIT 1`).get();
        expect(row.description).toContain(fileName);
        expect(row.user_id).toBe(adminId);
    });
    it('GET lists the created backup with metadata', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/admin/backup')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        const list = res.body.data.backups;
        const entry = list.find((b) => b.name === fileName);
        expect(entry).toBeDefined();
        expect(entry.sizeBytes).toBeGreaterThan(0);
        expect(typeof entry.createdAt).toBe('string');
        expect(res.body.data.lastBackupAt).toBeTruthy();
    });
    it('download streams the file; foreign names are rejected', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get(`/api/admin/backup/${fileName}/download`)
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
        expect(res.headers['content-disposition']).toContain('attachment');
        expect(res.body.length).toBeGreaterThan(0);
        const traversal = await (0, supertest_1.default)(app_1.default)
            .get(`/api/admin/backup/${encodeURIComponent('../../erp.db')}/download`)
            .set('Cookie', authCookie);
        expect(traversal.status).toBe(404);
    });
    it('DELETE removes the file and logs BACKUP_DELETE', async () => {
        const del = await (0, supertest_1.default)(app_1.default)
            .delete(`/api/admin/backup/${fileName}`)
            .set('Cookie', authCookie);
        expect(del.status).toBe(200);
        expect(fs_1.default.existsSync(path_1.default.join(BACKUP_DIR, fileName))).toBe(false);
        // Queued activity logger needs time to flush
        await new Promise((r) => setTimeout(r, 1600));
        const row = database_1.default.prepare(`SELECT COUNT(*) AS n FROM activity_log WHERE action = 'BACKUP_DELETE'`).get();
        expect(row.n).toBeGreaterThanOrEqual(1);
        const missing = await (0, supertest_1.default)(app_1.default)
            .delete(`/api/admin/backup/${fileName}`)
            .set('Cookie', authCookie);
        expect(missing.status).toBe(404);
    });
    it('denies create/delete to non-admin roles', async () => {
        const role = database_1.default.prepare(`SELECT id FROM roles WHERE role_name = 'User'`).get();
        database_1.default.prepare(`
      INSERT OR IGNORE INTO users (username, email, password_hash, full_name, role, is_active, role_id)
      VALUES ('bkuser', 'bkuser@x.io', ?, 'Bk User', 'user', 1, ?)
    `).run(bcrypt_1.default.hashSync('bk-pass-2026', 10), role.id);
        const userCookie = await getAuthCookie('bkuser', 'bk-pass-2026');
        expect(userCookie).not.toBe('');
        expect((await (0, supertest_1.default)(app_1.default)
            .post('/api/admin/backup')
            .set('Cookie', userCookie)).status).toBe(403);
        expect((await (0, supertest_1.default)(app_1.default)
            .delete('/api/admin/backup/erp-2026-01-01T00-00-00.db')
            .set('Cookie', userCookie)).status).toBe(403);
    });
});
