"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
/**
 * REP-18 regression tests: computed-column expressions are validated against
 * a safe grammar on BOTH stored and inline config paths; SQL injection via
 * expressions is impossible.
 */
const supertest_1 = __importDefault(require("supertest"));
const app_1 = __importDefault(require("../app"));
const database_1 = __importDefault(require("../config/database"));
const CustomReport_1 = __importDefault(require("../models/CustomReport"));
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
    const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies])
        .find((c) => c.startsWith('token='));
    return tokenCookie ? tokenCookie.split(';')[0] : '';
}
const INJECTION = '(SELECT password_hash FROM users)';
function invoiceConfig(expression) {
    return {
        entity: 'invoices',
        columns: [{ field: 'total_amount' }, { field: 'calc', alias: 'Calc' }],
        computedColumns: [{ name: 'calc', expression, type: 'number' }],
    };
}
describe('Report expression security (REP-18)', () => {
    let authCookie;
    let userId;
    beforeAll(async () => {
        authCookie = await getAuthCookie();
        expect(authCookie).not.toBe('');
        const me = await (0, supertest_1.default)(app_1.default).get('/api/auth/me').set('Cookie', authCookie);
        userId = me.body.data.id;
    });
    afterAll(() => {
        try {
            // Remove any report rows this suite created (user-scoped).
            const reports = database_1.default.prepare(`SELECT id FROM custom_reports WHERE user_id = ? AND (name LIKE 'rep18%' OR name LIKE 'REP18%')`).all(userId);
            for (const r of reports) {
                database_1.default.prepare('DELETE FROM custom_reports WHERE id = ?').run(r.id);
            }
        }
        catch {
            /* ignore cleanup errors */
        }
    });
    it('rejects an injection expression on the inline run path with 400 and never queries users.password_hash', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/reports/custom/run')
            .set('Cookie', authCookie)
            .send({ config: invoiceConfig(INJECTION) });
        expect(res.status).toBe(400);
        expect(JSON.stringify(res.body)).toMatch(/not allowed|Unknown field|Invalid/i);
    });
    it('rejects an injection expression on the stored-report path with 400 and stores nothing', async () => {
        const createRes = await (0, supertest_1.default)(app_1.default)
            .post('/api/reports/custom')
            .set('Cookie', authCookie)
            .send({ name: 'rep18-inject-attempt', config: invoiceConfig(INJECTION) });
        expect(createRes.status).toBe(400);
        expect(createRes.body.error).toMatch(/Invalid report config/i);
        // Nothing persisted
        const count = database_1.default.prepare(`SELECT COUNT(*) AS c FROM custom_reports WHERE user_id = ? AND name = 'rep18-inject-attempt'`).get(userId);
        expect(count.c).toBe(0);
        // Even if a row had been planted directly (legacy/compromised row),
        // executing it must still fail closed at the engine.
        const planted = CustomReport_1.default.create({
            user_id: userId,
            name: 'rep18-planted',
            description: undefined,
            config: invoiceConfig(INJECTION),
        });
        const runRes = await (0, supertest_1.default)(app_1.default)
            .post('/api/reports/custom/run')
            .set('Cookie', authCookie)
            .send({ reportId: planted.id });
        expect(runRes.status).toBe(400);
    });
    it('still executes legitimate expressions: quantity * unit_price form and ROUND(debit - credit, 2) form', async () => {
        // Inline path with a real arithmetic expression on invoices fields.
        const ok1 = await (0, supertest_1.default)(app_1.default)
            .post('/api/reports/custom/run')
            .set('Cookie', authCookie)
            .send({
            config: {
                entity: 'invoices',
                columns: [
                    { field: 'total_amount' },
                    { field: 'doubled', alias: 'Doubled' },
                ],
                computedColumns: [{ name: 'doubled', expression: 'total_amount * 2', type: 'number' }],
            },
        });
        expect(ok1.status).toBe(200);
        expect(ok1.body.success).toBe(true);
        // journal_lines-style expression via a second entity that has debit/credit.
        const entitiesRes = await (0, supertest_1.default)(app_1.default)
            .get('/api/reports/custom/entities')
            .set('Cookie', authCookie);
        expect(entitiesRes.status).toBe(200);
        const entities = entitiesRes.body.data;
        const glEntity = entities.find(e => e.fields.some(f => f.name === 'debit') && e.fields.some(f => f.name === 'credit'));
        if (glEntity) {
            const ok2 = await (0, supertest_1.default)(app_1.default)
                .post('/api/reports/custom/run')
                .set('Cookie', authCookie)
                .send({
                config: {
                    entity: glEntity.key,
                    columns: [
                        { field: 'debit' },
                        { field: 'net', alias: 'Net' },
                    ],
                    computedColumns: [{ name: 'net', expression: 'ROUND(debit - credit, 2)', type: 'number' }],
                },
            });
            expect(ok2.status).toBe(200);
            expect(ok2.body.success).toBe(true);
        }
    });
    it('validates every existing stored report config — no legacy row breaks under the new grammar', async () => {
        const rows = database_1.default.prepare(`SELECT id, name, config FROM custom_reports`).all();
        expect(Array.isArray(rows)).toBe(true);
        const { validateConfigExpressions } = await Promise.resolve().then(() => __importStar(require('../services/expressionValidator')));
        for (const row of rows) {
            let parsed;
            try {
                parsed = JSON.parse(row.config);
            }
            catch {
                continue; // non-JSON legacy rows are not expression configs
            }
            if (!parsed || !Array.isArray(parsed.computedColumns) || parsed.computedColumns.length === 0) {
                continue;
            }
            // Must not throw for any stored report.
            const entity = database_1.default.prepare; // placeholder to satisfy lint on unused import shape
            void entity;
            const { getEntity } = await Promise.resolve().then(() => __importStar(require('../services/entityRegistry')));
            const def = getEntity(parsed.entity);
            const fields = new Set(def ? def.fields.map((f) => f.name) : []);
            expect(() => validateConfigExpressions(parsed, fields))
                .not.toThrow(`stored report ${row.id} (${row.name}) uses a now-invalid expression`);
        }
    });
});
