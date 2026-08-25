# Settings: Backup section (view / create / download / delete) + collapsible cards

## Goal
1. New **Backup** section on the Settings page: last-backup status, "Back up now" button, list of existing backup files with **download** and **delete** actions per file.
2. All existing Settings sections (Date & Range, Company, Currency, Tax, Numbering, Other) become **collapsible, collapsed by default**.

Today backups only run from an in-process nightly scheduler (`server/src/services/backupService.ts`) — that's why activity log shows `BACKUP_CREATE` entries. There is no HTTP route or UI. We expose the existing service through an admin API and build the UI on top.

## Server (no schema change → no migration)

**1. `server/src/services/activityLogger.ts`**: add `ActionType.BACKUP_DELETE = 'BACKUP_DELETE'` (enum currently only has `BACKUP_CREATE`).

**2. `server/src/services/backupService.ts`**
- Extend `runBackup(opts?: { trigger?: 'manual' | 'nightly'; userId?: number | null })` — default unchanged (`Nightly`). Description becomes `Manual backup <file> (integrity ok)` for manual runs; the inline activity_log insert additionally binds `user_id` when provided (prepared statement, already parameterized).
- New exports: `listBackups()` → `{ name, sizeBytes, createdAt }[]` (erp-*.db, newest first), `lastBackupAt(): string | null`, and `deleteBackup(name)` — validates name against `^erp-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}\.db$`, verifies resolved path stays inside BACKUP_DIR (path-traversal guard), deletes the file.

**3. New `server/src/routes/adminBackup.ts`** (modeled on `adminHealth.ts`: `router.use(authenticateToken)` + per-route `requirePermission`, `{success, data, error}` envelope, try/catch, no stack leakage)
- `GET /api/admin/backup` (`admin`,`read`) → `{ backups: [...], lastBackupAt }`
- `POST /api/admin/backup` (`admin`,`create`) → runs `runBackup({trigger:'manual', userId:req.user.id})`; returns `{fileName}` or 500 on failure
- `GET /api/admin/backup/:name/download` (`admin`,`read`) → same name validation/traversal guard, then `res.download(...)`
- `DELETE /api/admin/backup/:name` (`admin`,`delete`) → validated `deleteBackup(name)`; activity logged via `logWithRequest` with user attribution

**4. Mount** in `server/src/app.ts` next to line 238: `app.use('/api/admin', adminBackupRoutes)`.

**5. Test** `server/src/__tests__/adminBackup.test.ts` (existing jest harness): POST creates file + `BACKUP_CREATE` log row described as "Manual backup…" with user attribution; GET lists it; download returns bytes; DELETE removes the file and logs `BACKUP_DELETE`; traversal-style names rejected on download & delete; non-admin without permission → 403.

## Flutter

**6. `lib/core/api/endpoints.dart`**: add `backup = '/admin/backup'`.

**7. New `lib/data/models/backup.dart` + `lib/data/repositories/backup_repository.dart`**: `BackupRepository` via `RepositoryClient` envelope helpers — `status()`, `create()`, `delete(name)`; `downloadBytes(name)` uses the `dioProvider` instance with `ResponseType.bytes` so the Bearer-token interceptor applies. Models: `BackupFile`, `BackupStatus`. Provider wired like `adminRepositoryProvider`.

**8. `lib/features/settings/settings_screen.dart`**
- Convert `_sectionCard` and `_dateRangeSection` to collapsible cards: Card + ExpansionTile (same styling as `_collapsible` helper in `customer_overview_tab.dart:230`), `initiallyExpanded: false`. Header row = icon + title + unsaved chip (visible while collapsed); fields + Save button live in expanded children.
- Add `_backupSection` (also collapsible): last backup time / "Never", "Back up now" FilledButton with spinner + snackbar feedback, list refresh; each backup file row shows name · size · date with **download** icon (pick target via `FilePicker.saveFile(fileName)` then write fetched bytes — established pattern from `csv_export.dart:706`) and **delete** icon gated by a confirmation dialog (destructive action). Rows are a compact ListView inside a settings card, not a primary data grid, so PlutoGrid is not used.

**9. Localization** — add keys to `lib/l10n/en.arb` and `lib/l10n/ur.arb`, run `flutter gen-l10n`: section title, last backup, never, back up now, backup success/failure, no-files empty text, download success/failure, delete label, delete-confirmation text, delete success/failure.

## Verification & self-audit
- Server: `npm run typecheck`, `npm run lint`, `npm test` (backup tests).
- Flutter: `flutter analyze`.
- No API contract break (additive endpoints); all external inputs parameterized; error handling + loading states complete; destructive delete requires confirmation; `graphify update .` at the end per AGENTS.md §18.
