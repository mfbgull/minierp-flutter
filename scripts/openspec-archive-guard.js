#!/usr/bin/env node
/**
 * openspec-archive-guard
 * ----------------------
 * Wraps `openspec archive` and refuses to archive a change whose tasks.md still
 * contains unchecked boxes (`- [ ]`).
 *
 * WHY THIS EXISTS
 * The `openspec` CLI is a globally-installed third-party package
 * (~/.nvm/.../lib/node_modules/@fission-ai/openspec). Its `archive` command
 * validates specs and then archives; it never inspects tasks.md. Proof:
 * `2026-08-22-inventory-integrity` sat in the archive with 18 of 19 tasks
 * unchecked, and those undone tasks were the fix for audit finding C-06.
 * Patching the CLI itself is not an option -- it is outside the repo, dies on
 * the next `npm update -g`, and cannot be covered by this repo's git tree.
 * So the gate lives here instead, in the repo, where it is reviewable.
 *
 * USAGE
 *   node scripts/openspec-archive-guard <change-name> [-- <openspec archive flags>]
 *
 *   Refuses by default. Two explicit escape hatches:
 *
 *   --force-incomplete        archive despite unchecked tasks
 *   --force-incomplete --reason "<text>"
 *                             mandatory with the above; the reason is written
 *                             to ARCHIVE-NOTES.md in the change directory
 *                             (appended, never overwritten) and echoed to
 *                             stdout, so the decision is auditable later.
 *
 * EXIT CODES
 *   0  archived (or dry-run succeeded)
 *   1  refused: unchecked tasks remain
 *   2  usage error
 *   3  change directory not found, or tasks.md missing
 */

'use strict';

const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const REPO_ROOT = process.env.OPENSPEC_GUARD_ROOT
  ? path.resolve(process.env.OPENSPEC_GUARD_ROOT)
  : path.resolve(__dirname, '..');
const CHANGES_DIR = path.join(REPO_ROOT, 'openspec', 'changes');

const UNCHECKED = /^\s*[-*]\s+\[ \]/;
const CHECKED = /^\s*[-*]\s+\[[xX]\]/;
const HOW_MANY = 5;

const USAGE = 2;
const UNVERIFIABLE = 3;

class UsageError extends Error {}
class ChangeError extends Error {}

function parseArgv(argv) {
  const change = argv[0];
  if (!change || change.startsWith('--')) {
    throw new UsageError('usage: openspec-archive-guard <change-name> [--force-incomplete --reason "<text>"] [-- <archive flags>]');
  }
  const opts = { change, forceIncomplete: false, reason: null, passthrough: [] };
  let passthrough = false;

  for (let i = 1; i < argv.length; i++) {
    const a = argv[i];
    if (passthrough) { opts.passthrough.push(a); continue; }
    if (a === '--') { passthrough = true; continue; }
    if (a === '--force-incomplete') { opts.forceIncomplete = true; continue; }
    if (a === '--reason') {
      opts.reason = argv[++i];
      if (!opts.reason) throw new UsageError('--reason requires a value');
      continue;
    }
    if (a.startsWith('--reason=')) { opts.reason = a.slice('--reason='.length); continue; }
    throw new UsageError(`unknown flag: ${a}`);
  }

  if (opts.forceIncomplete && !opts.reason) {
    throw new UsageError('--force-incomplete requires --reason "<text>". An incomplete archive with no recorded reason is exactly the failure this guard exists to prevent.');
  }
  return opts;
}

/** Return unchecked task lines from a change's tasks.md. */
function findUnchecked(changeDir) {
  const tasksPath = path.join(changeDir, 'tasks.md');
  if (!fs.existsSync(tasksPath)) return null;
  return fs.readFileSync(tasksPath, 'utf8')
    .split('\n')
    .map((l, i) => ({ line: l, n: i + 1 }))
    .filter(({ line }) => UNCHECKED.test(line));
}

function appendArchiveNote(changeDir, change, reason, uncheckedCount) {
  const notes = path.join(changeDir, 'ARCHIVE-NOTES.md');
  const stamp = new Date().toISOString();
  const entry =
    `\n## ${stamp} — archived with ${uncheckedCount} unchecked task(s)\n\n` +
    `**Reason:** ${reason}\n\n` +
    `The task-completion gate in \`scripts/openspec-archive-guard\` refused this\n` +
    `archive and was overridden with \`--force-incomplete\`. The unchecked work is\n` +
    `still outstanding and must be re-opened as a change.\n`;
  fs.appendFileSync(notes, entry);
  return notes;
}

function main() {
  let opts;
  let changeDir;
  let unchecked;
  try {
    opts = parseArgv(process.argv.slice(2));
    changeDir = path.join(CHANGES_DIR, opts.change);

    if (!fs.existsSync(changeDir)) {
      throw new ChangeError(`change not found: openspec/changes/${opts.change}`);
    }

    unchecked = findUnchecked(changeDir);
    if (unchecked === null) {
      throw new ChangeError(
        `no tasks.md in openspec/changes/${opts.change} — nothing to verify. ` +
        `Refusing to archive an unverifiable change.`
      );
    }
  } catch (e) {
    if (!(e instanceof UsageError) && !(e instanceof ChangeError)) throw e;
    process.stderr.write(`openspec-archive-guard: ${e.message}\n`);
    process.exit(e instanceof UsageError ? USAGE : UNVERIFIABLE);
  }

  if (unchecked.length > 0 && !opts.forceIncomplete) {
    process.stderr.write(
      `openspec-archive-guard: REFUSING to archive "${opts.change}"\n\n` +
      `  ${unchecked.length} unchecked task(s) in tasks.md:\n\n` +
      unchecked.slice(0, HOW_MANY)
        .map(({ n, line }) => `    tasks.md:${n}  ${line.trim()}`)
        .join('\n') +
      (unchecked.length > HOW_MANY ? `\n    … and ${unchecked.length - HOW_MANY} more` : '') +
      `\n\n  A change is not done until its tasks are done. To archive anyway, you must\n` +
      `  say why, and the reason is recorded in the change directory:\n\n` +
      `    node scripts/openspec-archive-guard ${opts.change} \\\n` +
      `      --force-incomplete --reason "<why this is acceptable>"\n\n`
    );
    process.exit(1);
  }

  const notesPath = unchecked.length > 0
    ? appendArchiveNote(changeDir, opts.change, opts.reason, unchecked.length)
    : null;

  if (unchecked.length > 0) {
    process.stderr.write(
      `openspec-archive-guard: --force-incomplete acknowledged. ` +
      `${unchecked.length} task(s) still unchecked; reason recorded in ` +
      `${path.relative(REPO_ROOT, notesPath)}\n\n`
    );
  }

  const args = ['archive', opts.change, ...opts.passthrough];
  try {
    execFileSync('openspec', args, { cwd: REPO_ROOT, stdio: 'inherit' });
  } catch (e) {
    process.exit(typeof e.status === 'number' ? e.status : 1);
  }
}

if (require.main === module) main();

module.exports = { parseArgv, findUnchecked, UNCHECKED, CHECKED };