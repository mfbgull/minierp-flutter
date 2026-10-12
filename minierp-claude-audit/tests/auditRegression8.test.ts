/**
 * Audit regression tests, round 8 — employee document files and backups.
 * Each test encodes CORRECT behaviour and is expected to FAIL on commit
 * 87f1265b until the finding is fixed (assertions are fix-agnostic).
 *
 *   FILE-001  deleting an employee document must never delete a file outside the upload folder,
 *             and a document can only be deleted through its own employee
 *   FILE-002  an uploaded file cannot be served as active content (html/svg/js)
 *   BK-001    backups work when the database directory contains an apostrophe
 *   BK-002    downloading a backup (a full copy of the database) leaves an audit row
 *   BK-003    every backup file the API lists can be downloaded and deleted
 *   BK-004    two backups requested in the same second both succeed
 *   BK-005    the backup folder can be redirected with BACKUP_DIR (as the CLI script allows)
 */
import request from 'supertest';
import bcrypt from 'bcrypt';
import fs from 'fs';
import os from 'os';
import path from 'path';
import app from '../app';
import db from '../config/database';
import { flushLogs } from '../services/activityLogger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

const PASSWORD = 'Regression#12345';
const uploadsDir = path.join(__dirname, '../../uploads');
const employeeDocsDir = path.join(uploadsDir, 'employees');
const created: string[] = [];

let adminCookie: string;
let updaterCookie: string;
let employeeA: number;
let employeeB: number;
let seq = 0;

function permissionId(module: string, action: string): number {
  let row = db.prepare('SELECT id FROM permissions WHERE module = ? AND action = ?').get(module, action) as { id: number } | undefined;
  if (!row) {
    row = {
      id: db.prepare(`INSERT INTO permissions (permission_name, module, action, description) VALUES (?, ?, ?, 'regression')`)
        .run(`${module}:${action}`, module, action).lastInsertRowid as number,
    };
  }
  return row.id;
}

async function createEmployee(cookie: string, code: string): Promise<number> {
  const res = await request(app).post('/api/employees').set('Cookie', cookie).send({
    first_name: 'Doc', last_name: code, employee_code: code, email: `${code}@example.test`,
    department_id: 1, position: 'Clerk', hire_date: '2026-01-01', salary: 1000,
  });
  expect(res.status).toBe(201);
  return (res.body?.data?.id ?? res.body?.id) as number;
}

beforeAll(async () => {
  fs.mkdirSync(employeeDocsDir, { recursive: true });
  adminCookie = await getAuthCookie();
  const roleId = db.prepare(`INSERT INTO roles (role_name, description, is_system_role, is_active) VALUES ('reg8_emp_updater', 'regression', 0, 1)`).run().lastInsertRowid as number;
  for (const action of ['read', 'update']) {
    db.prepare('INSERT OR IGNORE INTO role_permissions (role_id, permission_id) VALUES (?, ?)').run(roleId, permissionId('employees', action));
  }
  db.prepare(`
    INSERT INTO users (username, email, password_hash, full_name, role, role_id, is_active)
    VALUES ('reg8_updater', 'reg8_updater@example.test', ?, 'Updater', 'user', ?, 1)
  `).run(bcrypt.hashSync(PASSWORD, 10), roleId);
  const login = await request(app).post('/api/auth/login').send({ username: 'reg8_updater', password: PASSWORD });
  updaterCookie = ((login.headers['set-cookie'] as unknown as string[]) ?? []).find((c) => c.startsWith('token='))!.split(';')[0];
  employeeA = await createEmployee(adminCookie, 'REG8-A');
  employeeB = await createEmployee(adminCookie, 'REG8-B');
});

afterAll(() => {
  for (const f of created) fs.rmSync(f, { force: true });
});

describe('FILE-001: employee document deletion is contained', () => {
  it('control: deleting a document removes its own uploaded file', async () => {
    const add = await request(app).post(`/api/employees/${employeeA}/documents`).set('Cookie', updaterCookie)
      .field('document_name', 'Contract')
      .attach('file', Buffer.from('%PDF-1.4 regression'), { filename: 'contract.pdf', contentType: 'application/pdf' });
    expect(add.status).toBe(201);
    const docId = (add.body?.data?.id ?? add.body?.id) as number;
    const stored = (db.prepare('SELECT file_path FROM employee_documents WHERE id = ?').get(docId) as { file_path: string }).file_path;
    created.push(path.join(employeeDocsDir, stored));
    expect(fs.existsSync(path.join(employeeDocsDir, stored))).toBe(true);
    const del = await request(app).delete(`/api/employees/${employeeA}/documents/${docId}`).set('Cookie', updaterCookie);
    expect(del.status).toBe(204);
    expect(fs.existsSync(path.join(employeeDocsDir, stored))).toBe(false);
  });

  it('a crafted file_path cannot make the server delete a file outside the upload folder', async () => {
    seq += 1;
    const decoyName = `reg8-decoy-${Date.now()}-${seq}.txt`;
    const decoy = path.join(uploadsDir, decoyName);
    fs.writeFileSync(decoy, 'must survive');
    created.push(decoy);
    const add = await request(app).post(`/api/employees/${employeeA}/documents`).set('Cookie', updaterCookie)
      .send({ document_name: 'Crafted', file_path: `../${decoyName}` });
    if (add.status < 400) {
      const docId = (add.body?.data?.id ?? add.body?.id) as number;
      await request(app).delete(`/api/employees/${employeeA}/documents/${docId}`).set('Cookie', updaterCookie);
    } // rejecting the crafted path up front is also a valid fix
    expect(fs.existsSync(decoy)).toBe(true);
  });

  it('a document cannot be deleted through a different employee\'s URL', async () => {
    const add = await request(app).post(`/api/employees/${employeeA}/documents`).set('Cookie', updaterCookie)
      .send({ document_name: 'Belongs to A' });
    const docId = (add.body?.data?.id ?? add.body?.id) as number;
    const del = await request(app).delete(`/api/employees/${employeeB}/documents/${docId}`).set('Cookie', updaterCookie);
    expect(del.status).toBeGreaterThanOrEqual(400);
    expect(db.prepare('SELECT id FROM employee_documents WHERE id = ?').get(docId)).toBeDefined();
  });
});

describe('FILE-002: uploads cannot become active content', () => {
  it('an .html file declared as application/pdf is rejected or never served as HTML', async () => {
    const add = await request(app).post(`/api/employees/${employeeA}/documents`).set('Cookie', updaterCookie)
      .field('document_name', 'Looks like a PDF')
      .attach('file', Buffer.from('<script>alert(document.cookie)</script>'), { filename: 'evil.html', contentType: 'application/pdf' });
    if (add.status >= 400) return; // rejecting the mismatch is a valid fix
    const docId = (add.body?.data?.id ?? add.body?.id) as number;
    const stored = (db.prepare('SELECT file_path FROM employee_documents WHERE id = ?').get(docId) as { file_path: string }).file_path;
    created.push(path.join(employeeDocsDir, stored));
    const served = await request(app).get(`/api/employees/${employeeA}/documents/file/${stored}`).set('Cookie', updaterCookie);
    const type = String(served.headers['content-type'] ?? '');
    const disposition = String(served.headers['content-disposition'] ?? '');
    const isActive = /html|javascript|svg|xml/i.test(type);
    expect(isActive && !/attachment/i.test(disposition)).toBe(false);
  });
});

describe('BK-002 / BK-003 / BK-004: backup API behaviour', () => {
  const backupDir = (): string => path.join(process.env.DATABASE_PATH as string, 'backups');
  const auditRows = (): number =>
    (db.prepare("SELECT COUNT(*) AS n FROM activity_log WHERE action LIKE 'BACKUP%'").get() as { n: number }).n;
  const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

  it('downloading a backup writes an audit row', async () => {
    const made = await request(app).post('/api/admin/backup').set('Cookie', adminCookie).send({});
    expect(made.status).toBe(200);
    const name = made.body.data.fileName as string;
    await wait(1100); // keep later backups out of this one's second
    const before = auditRows();
    const dl = await request(app).get(`/api/admin/backup/${name}/download`).set('Cookie', adminCookie);
    expect(dl.status).toBe(200);
    flushLogs(); // the activity logger is queue-based; drain it before reading
    expect(auditRows()).toBeGreaterThan(before);
  });

  it('every backup the list shows (including CLI-named files) can be downloaded and deleted', async () => {
    const made = await request(app).post('/api/admin/backup').set('Cookie', adminCookie).send({});
    const source = path.join(backupDir(), made.body.data.fileName);
    const cliName = 'erp-backup-2026-01-01T00-00-00.db';
    fs.copyFileSync(source, path.join(backupDir(), cliName));
    const list = await request(app).get('/api/admin/backup').set('Cookie', adminCookie);
    const names = (list.body.data.backups as Array<{ name: string }>).map((b) => b.name);
    if (!names.includes(cliName)) return; // not listing it is also consistent
    const dl = await request(app).get(`/api/admin/backup/${cliName}/download`).set('Cookie', adminCookie);
    expect(dl.status).toBe(200);
    const del = await request(app).delete(`/api/admin/backup/${cliName}`).set('Cookie', adminCookie);
    expect(del.status).toBe(200);
  });

  it('two backups requested back to back both succeed', async () => {
    await wait(1100);
    const first = await request(app).post('/api/admin/backup').set('Cookie', adminCookie).send({});
    const second = await request(app).post('/api/admin/backup').set('Cookie', adminCookie).send({});
    expect(first.status).toBe(200);
    expect(second.status).toBe(200);
    expect(second.body.data.fileName).not.toBe(first.body.data.fileName);
  });
});

describe('BK-001 / BK-005: backup location handling', () => {
  function runIsolated(env: Record<string, string>): { result: string | null; dir: string } {
    const saved: Record<string, string | undefined> = {};
    for (const k of Object.keys(env)) saved[k] = process.env[k];
    Object.assign(process.env, env);
    let result: string | null = null;
    jest.isolateModules(() => {
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      const svc = require('../services/backupService');
      result = svc.runBackup({ trigger: 'manual' });
    });
    for (const k of Object.keys(env)) {
      if (saved[k] === undefined) delete process.env[k]; else process.env[k] = saved[k];
    }
    return { result, dir: env.DATABASE_PATH };
  }

  it('BK-001: a backup succeeds when the database directory contains an apostrophe', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "reg8-o'brien-"));
    const { result } = runIsolated({ DATABASE_PATH: dir });
    expect(result).not.toBeNull();
    expect(fs.readdirSync(path.join(dir, 'backups')).some((f) => f.endsWith('.db'))).toBe(true);
    fs.rmSync(dir, { recursive: true, force: true });
  }, 60000);

  it('BK-005: BACKUP_DIR redirects the in-app backup like it does the CLI script', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'reg8-db-'));
    const elsewhere = fs.mkdtempSync(path.join(os.tmpdir(), 'reg8-offsite-'));
    const { result } = runIsolated({ DATABASE_PATH: dir, BACKUP_DIR: elsewhere });
    expect(result).not.toBeNull();
    expect(fs.readdirSync(elsewhere).some((f) => /^erp-.*\.db$/.test(f))).toBe(true);
    fs.rmSync(dir, { recursive: true, force: true });
    fs.rmSync(elsewhere, { recursive: true, force: true });
  }, 60000);
});
