#!/usr/bin/env node
// l10n drift guard.
//
// en.arb is the template; ur.arb may lag it and gen-l10n silently falls back
// to English for missing keys. That fallback is deliberate — but an *unbounded*
// gap just grows, and a hand-written count in l10n.yaml goes stale the moment
// a key is added (it said 764/812 when the real counts were 2108/2053).
//
// This replaces that stale comment with a live check:
//   - orphaned keys (in ur.arb but not in the en.arb template) always fail —
//     they are dead translations that will never render;
//   - the fallback gap is capped, so it can shrink but not grow.
//
// Usage: node scripts/l10n-drift.js [--max-gap N]
const fs = require('fs');
const path = require('path');

// Cap on the fallback gap. Env var wins over the flag so CI can pin it.
const argIdx = process.argv.indexOf('--max-gap');
const flagGap = argIdx === -1 ? null : Number(process.argv[argIdx + 1]);
const MAX_GAP = Number(process.env.L10N_MAX_GAP ?? flagGap ?? 60);
if (!Number.isFinite(MAX_GAP) || MAX_GAP < 0) {
  console.error(`invalid --max-gap: ${process.argv[argIdx + 1]}`);
  process.exit(2);
}

const root = path.resolve(__dirname, '..');
const arbDir = path.join(root, 'lib', 'l10n');

/** Top-level message keys of an .arb file (nested @metadata excluded). */
function keysOf(file) {
  const text = fs.readFileSync(path.join(arbDir, file), 'utf8');
  const found = new Set();
  // Top-level keys are indented two spaces; @key metadata blocks are nested
  // deeper, so this indentation match picks up messages only.
  for (const m of text.matchAll(/^\s{2}"([^"]+)"\s*:/gm)) {
    if (!m[1].startsWith('@')) found.add(m[1]);
  }
  return found;
}

const en = keysOf('en.arb');
const ur = keysOf('ur.arb');

const missingInUr = [...en].filter((k) => !ur.has(k)).sort();
const orphaned = [...ur].filter((k) => !en.has(k)).sort();

console.log(`en.arb: ${en.size} keys`);
console.log(`ur.arb: ${ur.size} keys`);
console.log(`fallback gap (missing in ur): ${missingInUr.length}`);
console.log(`orphaned (in ur, not in en): ${orphaned.length}`);

let failed = false;

if (orphaned.length > 0) {
  failed = true;
  console.error('\nORPHANED keys — in ur.arb but absent from the en.arb template:');
  for (const k of orphaned) console.error(`  ${k}`);
}

if (missingInUr.length > MAX_GAP) {
  failed = true;
  console.error(
    `\nGAP REGRESSED: ${missingInUr.length} keys missing from ur.arb (cap is ${MAX_GAP}).\n` +
      'Either translate them in lib/l10n/ur.arb or raise L10N_MAX_GAP deliberately.',
  );
} else {
  console.log(`gap within cap (${MAX_GAP})`);
}

process.exit(failed ? 1 : 0);
