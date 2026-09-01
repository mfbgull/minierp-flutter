"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const supertest_1 = __importDefault(require("supertest"));
const app_1 = __importDefault(require("../app"));
const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
    throw new Error('TEST_ADMIN_PASSWORD environment variable must be set for integration tests.');
}
let authCookie;
async function getAuthCookie() {
    const res = await (0, supertest_1.default)(app_1.default)
        .post('/api/auth/login')
        .send({ username: 'admin', password: TEST_PASSWORD });
    const cookies = res.headers['set-cookie'];
    if (!cookies)
        return '';
    const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies])
        .find((c) => c.startsWith('token='));
    if (!tokenCookie)
        return '';
    return tokenCookie.split(';')[0];
}
describe('Owner Personal Loans', () => {
    beforeAll(async () => {
        authCookie = await getAuthCookie();
        expect(authCookie).toBeTruthy();
    });
    it('GET /api/owner-equity/personal-loans/summary returns zeros when empty', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/owner-equity/personal-loans/summary')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body.data.total_lent).toBe(0);
        expect(res.body.data.total_repaid).toBe(0);
        expect(res.body.data.total_pending).toBe(0);
        expect(res.body.data.active_count).toBe(0);
    });
    it('POST /api/owner-equity/personal-loans creates a pending loan', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/owner-equity/personal-loans')
            .set('Cookie', authCookie)
            .send({
            borrower_name: 'Ali Khan',
            amount: 50000,
            currency: 'PKR',
            loan_date: '2026-08-01',
            due_date: '2026-12-31',
            purpose: 'Medical',
            notes: 'Emergency medical',
        });
        expect(res.status).toBe(201);
        expect(res.body.success).toBe(true);
        expect(res.body.data.borrower_name).toBe('Ali Khan');
        expect(res.body.data.amount).toBe(50000);
        expect(res.body.data.balance).toBe(50000);
        expect(res.body.data.status).toBe('pending');
        expect(res.body.data.currency).toBe('PKR');
    });
    it('GET /api/owner-equity/personal-loans lists the created loan', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/owner-equity/personal-loans')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(Array.isArray(res.body.data)).toBe(true);
        expect(res.body.data.length).toBeGreaterThanOrEqual(1);
    });
    it('GET /api/owner-equity/personal-loans/:id returns detail without repayments', async () => {
        const listRes = await (0, supertest_1.default)(app_1.default)
            .get('/api/owner-equity/personal-loans')
            .set('Cookie', authCookie);
        const loanId = listRes.body.data[0].id;
        const res = await (0, supertest_1.default)(app_1.default)
            .get(`/api/owner-equity/personal-loans/${loanId}`)
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body.data.id).toBe(loanId);
        expect(res.body.data.repayments).toEqual([]);
    });
    it('POST /api/owner-equity/personal-loans/:id/repayments records a repayment and updates balance/status', async () => {
        const listRes = await (0, supertest_1.default)(app_1.default)
            .get('/api/owner-equity/personal-loans')
            .set('Cookie', authCookie);
        const loanId = listRes.body.data[0].id;
        const res = await (0, supertest_1.default)(app_1.default)
            .post(`/api/owner-equity/personal-loans/${loanId}/repayments`)
            .set('Cookie', authCookie)
            .send({
            amount: 20000,
            payment_date: '2026-08-15',
            notes: 'Partial return',
        });
        expect(res.status).toBe(201);
        expect(res.body.success).toBe(true);
        expect(res.body.data.loan_balance).toBe(30000);
        expect(res.body.data.loan_status).toBe('partial');
    });
    it('GET /api/owner-equity/personal-loans/:id returns repayments', async () => {
        const listRes = await (0, supertest_1.default)(app_1.default)
            .get('/api/owner-equity/personal-loans')
            .set('Cookie', authCookie);
        const loanId = listRes.body.data[0].id;
        const res = await (0, supertest_1.default)(app_1.default)
            .get(`/api/owner-equity/personal-loans/${loanId}`)
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(Array.isArray(res.body.data.repayments)).toBe(true);
        expect(res.body.data.repayments.length).toBe(1);
        expect(res.body.data.repayments[0].amount).toBe(20000);
    });
    it('summary reflects repayment totals', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/owner-equity/personal-loans/summary')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
        expect(res.body.data.total_repaid).toBe(20000);
        expect(res.body.data.total_pending).toBe(30000);
        expect(res.body.data.active_count).toBe(1);
    });
    it('rejects repayment exceeding balance', async () => {
        const listRes = await (0, supertest_1.default)(app_1.default)
            .get('/api/owner-equity/personal-loans')
            .set('Cookie', authCookie);
        const loanId = listRes.body.data[0].id;
        const res = await (0, supertest_1.default)(app_1.default)
            .post(`/api/owner-equity/personal-loans/${loanId}/repayments`)
            .set('Cookie', authCookie)
            .send({ amount: 50000, payment_date: '2026-08-16' });
        expect(res.status).toBe(400);
        expect(res.body.success).toBe(false);
    });
    it('settles loan when repayment clears balance', async () => {
        const listRes = await (0, supertest_1.default)(app_1.default)
            .get('/api/owner-equity/personal-loans')
            .set('Cookie', authCookie);
        const loanId = listRes.body.data[0].id;
        const res = await (0, supertest_1.default)(app_1.default)
            .post(`/api/owner-equity/personal-loans/${loanId}/repayments`)
            .set('Cookie', authCookie)
            .send({ amount: 30000, payment_date: '2026-08-20' });
        expect(res.status).toBe(201);
        expect(res.body.data.loan_balance).toBe(0);
        expect(res.body.data.loan_status).toBe('settled');
    });
    it('blocks repayment on settled loan', async () => {
        const listRes = await (0, supertest_1.default)(app_1.default)
            .get('/api/owner-equity/personal-loans')
            .set('Cookie', authCookie);
        const loanId = listRes.body.data[0].id;
        const res = await (0, supertest_1.default)(app_1.default)
            .post(`/api/owner-equity/personal-loans/${loanId}/repayments`)
            .set('Cookie', authCookie)
            .send({ amount: 1, payment_date: '2026-08-21' });
        expect(res.status).toBe(400);
        expect(res.body.success).toBe(false);
    });
    it('DELETE /api/owner-equity/personal-loans/:id/repayments/:repId restores balance/status', async () => {
        const listRes = await (0, supertest_1.default)(app_1.default)
            .get('/api/owner-equity/personal-loans')
            .set('Cookie', authCookie);
        const loanId = listRes.body.data[0].id;
        const detailRes = await (0, supertest_1.default)(app_1.default)
            .get(`/api/owner-equity/personal-loans/${loanId}`)
            .set('Cookie', authCookie);
        const repId = detailRes.body.data.repayments[0].id;
        const res = await (0, supertest_1.default)(app_1.default)
            .delete(`/api/owner-equity/personal-loans/${loanId}/repayments/${repId}`)
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        // After deleting the first repayment (20000), one repayment (30000) remains.
        expect(res.body.data.loan_balance).toBe(20000);
        expect(res.body.data.loan_status).toBe('partial');
    });
    it('blocks delete loan with repayments', async () => {
        const listRes = await (0, supertest_1.default)(app_1.default)
            .get('/api/owner-equity/personal-loans')
            .set('Cookie', authCookie);
        const loanId = listRes.body.data[0].id;
        const res = await (0, supertest_1.default)(app_1.default)
            .delete(`/api/owner-equity/personal-loans/${loanId}`)
            .set('Cookie', authCookie);
        expect(res.status).toBe(400);
        expect(res.body.success).toBe(false);
    });
    it('allows delete loan without repayments', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/owner-equity/personal-loans')
            .set('Cookie', authCookie)
            .send({
            borrower_name: 'Sara Ahmed',
            amount: 1000,
            loan_date: '2026-09-01',
        });
        const loanId = res.body.data.id;
        const del = await (0, supertest_1.default)(app_1.default)
            .delete(`/api/owner-equity/personal-loans/${loanId}`)
            .set('Cookie', authCookie);
        expect(del.status).toBe(200);
        expect(del.body.success).toBe(true);
    });
    it('write-off sets status to written_off and balance to 0', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/owner-equity/personal-loans')
            .set('Cookie', authCookie)
            .send({
            borrower_name: 'Bilal',
            amount: 5000,
            loan_date: '2026-09-02',
        });
        const loanId = res.body.data.id;
        const update = await (0, supertest_1.default)(app_1.default)
            .put(`/api/owner-equity/personal-loans/${loanId}`)
            .set('Cookie', authCookie)
            .send({ status: 'written_off', balance: 0 });
        expect(update.status).toBe(200);
        expect(update.body.data.status).toBe('written_off');
        expect(update.body.data.balance).toBe(0);
    });
    describe('borrowers', () => {
        it('create borrower', async () => {
            const res = await (0, supertest_1.default)(app_1.default)
                .post('/api/owner-equity/borrowers')
                .set('Cookie', authCookie)
                .send({ name: 'Test Borrower', phone: '+92-300-1234567' });
            expect(res.status).toBe(201);
            expect(res.body.success).toBe(true);
            expect(res.body.data.name).toBe('Test Borrower');
        });
        it('list borrowers defaults to active', async () => {
            const res = await (0, supertest_1.default)(app_1.default)
                .get('/api/owner-equity/borrowers')
                .set('Cookie', authCookie);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(Array.isArray(res.body.data)).toBe(true);
        });
        it('deactivate borrower with loans is blocked', async () => {
            const listRes = await (0, supertest_1.default)(app_1.default)
                .get('/api/owner-equity/borrowers')
                .set('Cookie', authCookie);
            const borrowerId = listRes.body.data[0].id;
            const res = await (0, supertest_1.default)(app_1.default)
                .put(`/api/owner-equity/borrowers/${borrowerId}/deactivate`)
                .set('Cookie', authCookie);
            expect(res.status).toBe(400);
            expect(res.body.success).toBe(false);
        });
        it('unlink borrower without link is rejected', async () => {
            const listRes = await (0, supertest_1.default)(app_1.default)
                .get('/api/owner-equity/borrowers')
                .set('Cookie', authCookie);
            const borrowerId = listRes.body.data[0].id;
            const res = await (0, supertest_1.default)(app_1.default)
                .put(`/api/owner-equity/borrowers/${borrowerId}/unlink`)
                .set('Cookie', authCookie);
            expect(res.status).toBe(400);
            expect(res.body.success).toBe(false);
        });
        it('merge borrowers', async () => {
            const listRes = await (0, supertest_1.default)(app_1.default)
                .get('/api/owner-equity/borrowers')
                .set('Cookie', authCookie);
            const sourceId = listRes.body.data[0].id;
            const createRes = await (0, supertest_1.default)(app_1.default)
                .post('/api/owner-equity/borrowers')
                .set('Cookie', authCookie)
                .send({ name: 'Merge Target' });
            const targetId = createRes.body.data.id;
            const res = await (0, supertest_1.default)(app_1.default)
                .post(`/api/owner-equity/borrowers/${sourceId}/merge`)
                .set('Cookie', authCookie)
                .send({ target_borrower_id: targetId });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data.source_deactivated).toBe(true);
        });
    });
});
