"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const fs_1 = __importDefault(require("fs"));
const os_1 = __importDefault(require("os"));
const path_1 = __importDefault(require("path"));
const better_sqlite3_1 = __importDefault(require("better-sqlite3"));
/**
 * Task 7.6: backup produced while WAL holds committed txns passes
 * integrity_check and contains those rows on restore into a fresh file.
 */
describe('backup WAL durability (task 7.6)', () => {
    it('VACUUM INTO captures committed WAL transactions; copy passes integrity_check', () => {
        const dir = fs_1.default.mkdtempSync(path_1.default.join(os_1.default.tmpdir(), 'bk-wal-'));
        const main = path_1.default.join(dir, 'erp.db');
        const db = new better_sqlite3_1.default(main);
        db.pragma('journal_mode = WAL');
        db.pragma('synchronous = NORMAL');
        // Committed txn that lives in the -wal file (not yet checkpointed)
        db.exec(`CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)`);
        db.prepare(`INSERT INTO t (v) VALUES ('committed-in-wal')`).run();
        // VACUUM INTO from the live connection
        const target = path_1.default.join(dir, 'backup.db');
        db.exec(`VACUUM INTO '${target}'`);
        // integrity check on the copy
        const copy = new better_sqlite3_1.default(target, { readonly: true });
        expect(copy.pragma('integrity_check', { simple: true })).toBe('ok');
        // Row present when the copy is opened as a live database (restore = use the file)
        const r2 = new better_sqlite3_1.default(target, { readonly: true });
        const row = r2.prepare('SELECT v FROM t').get();
        r2.close();
        copy.close();
        db.close();
        expect(row?.v).toBe('committed-in-wal');
        fs_1.default.rmSync(dir, { recursive: true, force: true });
    });
});
//# sourceMappingURL=backupWal.test.js.map