#!/usr/bin/env node
/**
 * Tests for openspec-archive-guard.
 *
 * These cover the gate's own logic (arg parsing + unchecked-task detection) and
 * prove the refusal actually fires on a fixture change that has unchecked
 * tasks — the anti-vacuity requirement from known-issues.md: a guard that has
 * never been seen to fail is not a guard.
 *
 * Run: node scripts/openspec-archive-guard.test.js
 */

'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');

const GUARD = path.join(__dirname, 'openspec-archive-guard.js');
let passed = 0;
const failures = [];

function test(name, fn) {
  try { fn(); passed++; process.stdout.write(`  ✓ ${name}\n`); }
  catch (e) { failures.push([name, e]); process.stdout.write(`  ✗ ${name}\n      ${e.message}\n`); }
}

/** Build a throwaway repo-shaped fixture with one change. */
function fixture(taskLines) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'osguard-'));
  const dir = path.join(root, 'openspec', 'changes', 'fix-a-thing');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'tasks.md'), '# Tasks\n\n' + taskLines + '\n');
  fs.writeFileSync(path.join(dir, 'proposal.md'), '# Proposal\n\n## Why\nbecause\n');
  return { root, dir, change: 'fix-a-thing' };
}

function runGuard(args, cwd, extraEnv = {}) {
  return spawnSync(process.execPath, [GUARD, ...args], {
    cwd,
    encoding: 'utf8',
    env: { ...process.env, OPENSPEC_GUARD_ROOT: cwd, ...extraEnv },
  });
}

/** Stub `openspec` on PATH so we observe pass-through without invoking the real CLI. */
function stubCli(root) {
  const bin = path.join(root, 'stubbin');
  fs.mkdirSync(bin, { recursive: true });
  const p = path.join(bin, 'openspec');
  fs.writeFileSync(p, '#!/bin/sh\necho "STUB-CALLED $*"\nexit 0\n', { mode: 0o755 });
  return { bin, PATH: `${bin}:${process.env.PATH}` };
}

// ── parseArgv ───────────────────────────────────────────────────────────────
test('rejects --force-incomplete without --reason', () => {
  const r = runGuard(['fix-a-thing', '--force-incomplete'], process.cwd());
  assert.strictEqual(r.status, 2, 'must exit 2');
  assert.match(r.stderr, /requires --reason/);
});

test('accepts --force-incomplete with --reason (both spellings)', () => {
  const { parseArgv } = require(GUARD);
  const a = parseArgv(['c', '--force-incomplete', '--reason', 'why']);
  assert.strictEqual(a.forceIncomplete, true);
  assert.strictEqual(a.reason, 'why');
  const b = parseArgv(['c', '--force-incomplete', '--reason=why2']);
  assert.strictEqual(b.reason, 'why2');
});

test('rejects unknown flags and a missing change name', () => {
  const { parseArgv } = require(GUARD);
  assert.throws(() => parseArgv([]), /usage/);
  assert.throws(() => parseArgv(['c', '--bogus']), /unknown flag/);
});

// ── findUnchecked ───────────────────────────────────────────────────────────
test('detects unchecked and ignores checked tasks', () => {
  const { findUnchecked } = require(GUARD);
  const { dir } = fixture('- [x] done\n- [ ] not done\n- [X] also done\n- [ ] another\n');
  const found = findUnchecked(dir);
  assert.strictEqual(found.length, 2, 'exactly two unchecked');
  assert.ok(found.every((f) => f.n > 0));
});

test('returns null when tasks.md is absent', () => {
  const { findUnchecked } = require(GUARD);
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'osguard-'));
  fs.mkdirSync(path.join(root, 'tasks-not-here'));
  assert.strictEqual(findUnchecked(path.join(root, 'tasks-not-here')), null);
});

// ── the refusal actually fires (anti-vacuity) ───────────────────────────────
test('REFUSES a change with unchecked tasks — exit 1, names them, does not archive', () => {
  const { root, dir, change } = fixture('- [x] a\n- [ ] b is broken\n- [ ] c also broken');
  const r = runGuard([change], root);

  assert.strictEqual(r.status, 1, 'exit 1 = refused');
  assert.match(r.stderr, /REFUSING to archive/);
  assert.match(r.stderr, /2 unchecked task/);
  assert.match(r.stderr, /b is broken/);
  // it must not have run the real CLI
  assert.ok(!fs.existsSync(path.join(root, 'openspec', 'changes', 'archive', change)),
    'must NOT have archived');
  // and must not have written notes on a plain refusal
  assert.ok(!fs.existsSync(path.join(dir, 'ARCHIVE-NOTES.md')),
    'a plain refusal must not record an override note');
});

test('a fully-checked change does NOT trip the guard (no false positive)', () => {
  const { root, change } = fixture('- [x] one\n- [x] two');
  const r = runGuard([change], root, stubCli(root));
  assert.strictEqual(r.status, 0, 'exit 0 = passed through');
  assert.match(r.stdout, /STUB-CALLED archive fix-a-thing/);
});

test('--force-incomplete records the reason in ARCHIVE-NOTES.md (append, never clobber)', () => {
  const { root, dir, change } = fixture('- [ ] still broken');
  const notes = path.join(dir, 'ARCHIVE-NOTES.md');
  fs.writeFileSync(notes, '## earlier entry that must survive\n');

  const r = runGuard([change, '--force-incomplete', '--reason', 'superseded by C-06 work'], root, stubCli(root));

  assert.strictEqual(r.status, 0);
  const body = fs.readFileSync(notes, 'utf8');
  assert.match(body, /earlier entry that must survive/, 'must append, not overwrite');
  assert.match(body, /superseded by C-06 work/, 'reason is recorded');
  assert.match(body, /1 unchecked task/, 'count is recorded');
});

test('refuses a change directory with no tasks.md — unverifiable', () => {
  const { root, change } = fixture('- [x] only');
  fs.unlinkSync(path.join(root, 'openspec', 'changes', change, 'tasks.md'));
  const r = runGuard([change], root);
  assert.strictEqual(r.status, 3);
  assert.match(r.stderr, /nothing to verify/);
});

test('refuses a nonexistent change with exit 3', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'osguard-'));
  fs.mkdirSync(path.join(root, 'openspec', 'changes'), { recursive: true });
  const r = runGuard(['no-such-change'], root);
  assert.strictEqual(r.status, 3);
  assert.match(r.stderr, /change not found/);
});

// ── the real repo passes its own gate ───────────────────────────────────────
test('every archived change in this repo now has zero unchecked tasks', () => {
  const { findUnchecked } = require(GUARD);
  const repo = path.resolve(__dirname, '..');
  const arch = path.join(repo, 'openspec', 'changes', 'archive');
  const offenders = [];
  for (const c of fs.readdirSync(arch)) {
    const found = findUnchecked(path.join(arch, c));
    if (found && found.length) offenders.push(`${c} (${found.length})`);
  }
  assert.deepStrictEqual(offenders, [],
    `these archived changes have unchecked tasks:\n  ${offenders.join('\n  ')}`);
});

test('truncation shows the first N unchecked tasks, and says how many remain', () => {
  const many = Array.from({ length: 9 }, (_, i) => `- [ ] task ${i + 1}`).join('\n');
  const { root, change } = fixture(many);
  const r = runGuard([change], root);
  assert.match(r.stderr, /9 unchecked task/);
  assert.match(r.stderr, /task 5/);
  assert.match(r.stderr, /… and 4 more/);
});

process.stdout.write(`\n${passed} passed, ${failures.length} failed\n`);
if (failures.length) process.exit(1);