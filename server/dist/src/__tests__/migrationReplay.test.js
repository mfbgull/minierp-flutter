"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const fs_1 = __importDefault(require("fs"));
const os_1 = __importDefault(require("os"));
const path_1 = __importDefault(require("path"));
/**
 * Migration replay suite (audit-remediation task 2.6 / financial-test-invariants).
 * Boots the real ledgered migration path twice against the same database and
 * asserts zero errors + identical sqlite_master after the second boot.
 */
describe('migration replay (task 2.6)', () => {
    it('boots the ledger twice with identical schema and no re-execution', () => {
        const dir = fs_1.default.mkdtempSync(path_1.default.join(os_1.default.tmpdir(), 'mig-replay-'));
        process.env.DATABASE_PATH = dir;
        process.env.NODE_ENV = 'test';
        process.env.JWT_SECRET = 'replay-test-secret';
        process.env.DEFAULT_ADMIN_PASSWORD = 'replay-admin-pass';
        // eslint-disable-next-line @typescript-eslint/no-var-requires
        // eslint-disable-next-line @typescript-eslint/no-require-imports
        const dbModule = require('../config/database').default;
        const fingerprint = () => JSON.stringify(dbModule.prepare(`SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name`).all());
        const appliedCount = () => dbModule.prepare('SELECT COUNT(*) AS n FROM schema_migrations').get().n;
        const first = fingerprint();
        const firstApplied = appliedCount();
        expect(firstApplied).toBeGreaterThan(40); // full chain registered
        // Second boot of the same process = every runLedgered call skips (recorded).
        // Force a "second boot" by clearing require cache and re-importing.
        jest.resetModules();
        // eslint-disable-next-line @typescript-eslint/no-var-requires
        // eslint-disable-next-line @typescript-eslint/no-require-imports
        const db2 = (require('../config/database').default);
        const second = JSON.stringify(db2.prepare(`SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name`).all());
        expect(second).toBe(first);
        // Ledger unchanged — nothing re-executed or double-recorded
        expect(db2.prepare('SELECT COUNT(*) AS n FROM schema_migrations').get().n).toBe(firstApplied);
        fs_1.default.rmSync(dir, { recursive: true, force: true });
    });
});
//# sourceMappingURL=migrationReplay.test.js.map