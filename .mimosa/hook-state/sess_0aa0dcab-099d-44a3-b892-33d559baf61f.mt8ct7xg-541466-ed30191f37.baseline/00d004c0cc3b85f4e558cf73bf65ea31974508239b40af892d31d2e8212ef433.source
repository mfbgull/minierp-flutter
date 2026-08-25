#!/usr/bin/env node
/**
 * Restore l10n labels that were clobbered by a generator pass.
 *
 * 747 of 1,635 keys in en.arb (and the same in ur.arb) hold machine
 * placeholder values ("Activitylogaction", "Bomitems", ...) where the
 * key was lowercased/capitalized instead of the real translation. The
 * real translations exist in git HEAD. This replaces exactly those
 * placeholder values with the HEAD strings.
 *
 * A handful of keys were also corrupted into "Keyname {param}" strings
 * (e.g. `paymentsErrorAmountExceedsBalance` -> "Paymentexceedsbalance
 * {remainingBalance}"). For those the HEAD *text* is restored but the
 * *placeholder parameter names* already in the generated getters (and
 * used by call sites) are preserved.
 *
 * Intentional changes are left untouched:
 *   - real translations (e.g. dashboardWelcome = "Welcome back")
 *   - the recent cashpos and cashrecon label fixes
 *   - drpDaysSelected (already a real "{n} days selected" translation)
 *
 * Usage: node scripts/restore-l10n-labels.js
 */
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const langs = ['en', 'ur'];

function loadHead(lang) {
  const { execFileSync } = require('child_process');
  const out = execFileSync('git', ['show', `HEAD:lib/l10n/${lang}.arb`], { cwd: root });
  return JSON.parse(out.toString('utf8'));
}

// Keys corrupted into "Keyname {param}" text. For these we restore the
// HEAD wording but keep the CURRENT placeholder names (getters + call
// sites already use them). Param substitution is positional: head params
// are replaced by cur params in order.
const PARAM_RESTORE = new Set([
  'activitylogCleanupsuccess',
  'usermanagementPermissionsubtitle',
  'customersDays',
  'paymentsErrorAmountExceedsBalance',
  'productionShortfallLine',
  'quotationsConvertedmsg',
  'reportsDays1_30',
  'reportsDays31_60',
  'reportsDays61_90',
  'reportsDays90plus',
]);

const isPurePlaceholder = (k, v) =>
  typeof v === 'string' &&
  v === k[0].toUpperCase() + k.slice(1).toLowerCase() &&
  /^[A-Z][a-z0-9]+$/.test(v);

function substituteParams(text, headParams, curParams) {
  if (headParams.length === 0) return text;
  let out = text;
  headParams.forEach((hp, i) => {
    out = out.split(`{${hp}}`).join(`{${curParams[i] ?? hp}}`);
  });
  return out;
}

let totalRestored = 0;
for (const lang of langs) {
  const file = path.join(root, 'lib', 'l10n', `${lang}.arb`);
  const cur = JSON.parse(fs.readFileSync(file, 'utf8'));
  const head = loadHead(lang);

  let restored = 0;
  const keys = Object.keys(cur).filter((k) => !k.startsWith('@'));
  for (const k of keys) {
    const v = cur[k];
    if (typeof head[k] !== 'string') continue;

    if (isPurePlaceholder(k, v)) {
      cur[k] = head[k];
      restored++;
      continue;
    }

    if (PARAM_RESTORE.has(k)) {
      // Corrupted "Keyname {param}" text: keep cur params, restore head wording.
      const headParams = [...head[k].matchAll(/\{(\w+)\}/g)].map((m) => m[1]);
      const curParams = [...v.matchAll(/\{(\w+)\}/g)].map((m) => m[1]);
      cur[k] = substituteParams(head[k], headParams, curParams);
      restored++;
    }
  }

  fs.writeFileSync(file, JSON.stringify(cur, null, 2) + '\n', 'utf8');
  console.log(`${lang}.arb: restored ${restored} labels`);
  totalRestored += restored;
}
console.log(`Total restored: ${totalRestored}`);
