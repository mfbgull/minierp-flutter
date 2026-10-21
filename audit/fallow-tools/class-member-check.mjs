// Owner-strict class-member verification.
// A member of class C is "used" ONLY via `C.member`, `C['member']`, or `this.member`
// inside class C. A different class's identically-named method does NOT count.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = '/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter';
const SNAPSHOT = process.argv[2] || 'audit/fallow-tools/snapshot.json';
const j = JSON.parse(fs.readFileSync(path.join(ROOT, SNAPSHOT), 'utf8'));
const cm = j.check.unused_class_members;

const NOISE = /^(server\/graphify-out\/|server\/client\/dist\/|coverage\/|build\/|graphify-out\/|node_modules\/|server\/node_modules\/|audit\/)/;
const files = execFileSync('git', ['ls-files'], { cwd: ROOT, encoding: 'utf8' })
  .split('\n').filter(Boolean).filter(f => !NOISE.test(f) && /\.(ts|tsx|js|jsx|mjs|cjs)$/.test(f));

const corpus = [];
for (const f of files) {
  try { corpus.push({ file: f, text: fs.readFileSync(path.join(ROOT, f), 'utf8') }); } catch {}
}

// Resolve the REAL owner class of a class-member finding.
function resolveOwner(file, reportedParent) {
  const c = corpus.find(x => x.file === file);
  if (!c) return { names: [], declRanges: [] };
  const names = new Set();
  if (reportedParent && reportedParent !== 'default') names.add(reportedParent);
  // export class X
  for (const m of c.text.matchAll(/^export\s+(?:abstract\s+)?class\s+([A-Za-z_$][\w$]*)/gm)) names.add(m[1]);
  // export default X;  (identifier default export)
  for (const m of c.text.matchAll(/^export\s+default\s+([A-Za-z_$][\w$]*)\s*;/gm)) names.add(m[1]);
  // class X (non-exported) -- only if it is the only class and is the default export target
  const defId = c.text.match(/^export\s+default\s+([A-Za-z_$][\w$]*)\s*;/m);
  if (defId) {
    const re = new RegExp(`^(?:export\\s+)?(?:abstract\\s+)?class\\s+${defId[1]}\\b`, 'm');
    if (re.test(c.text)) names.add(defId[1]);
  }
  return { names: [...names], text: c.text };
}

const ESC = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const out = [];
for (const f of cm) {
  const owner = resolveOwner(f.path, f.parent_name);
  const ownerRe = owner.names.length ? new RegExp(`\\b(${owner.names.map(ESC).join('|')})\\s*(\\.\\s*${ESC(f.member_name)}\\b|\\[\\s*['"\`]${ESC(f.member_name)}['"\`]\\s*\\])`) : null;
  const declRe = new RegExp(`^\\s*(?:static\\s+|async\\s+|public\\s+|private\\s+|readonly\\s+)*${ESC(f.member_name)}\\s*\\(`);
  const external = [];
  const internal = [];
  for (const { file, text } of corpus) {
    const inDecl = file === f.path;
    text.split('\n').forEach((line, i) => {
      if (!new RegExp(`\\b${ESC(f.member_name)}\\b`).test(line)) return;
      if (ownerRe && ownerRe.test(line)) {
        (inDecl ? internal : external).push({ file, line: i + 1, text: line.trim() });
        return;
      }
      if (inDecl && declRe.test(line)) return; // the declaration itself
      if (inDecl) {
        // same-file reference that is NOT `Owner.member` and not the declaration
        internal.push({ file, line: i + 1, text: line.trim(), loose: true });
      }
    });
  }
  const qualifiedExternal = external;
  const looseInternal = internal.filter(x => x.loose);
  out.push({
    path: f.path, line: f.line, member: f.member_name,
    reportedParent: f.parent_name, resolvedOwner: owner.names,
    qualifiedExternal, looseInternal,
    verdict: qualifiedExternal.length ? 'FALSE-POSITIVE' : (looseInternal.length ? 'REDUNDANT-EXPORT' : 'CONFIRMED-DEAD'),
    evidence: qualifiedExternal.slice(0, 3).map(x => `${x.file}:${x.line}`),
  });
}

const tally = out.reduce((a, r) => (a[r.verdict] = (a[r.verdict] || 0) + 1, a), {});
console.log('class-member findings:', out.length, JSON.stringify(tally));
console.log('\n--- owner resolution failures (reported "default" and no owner found) ---');
console.log(out.filter(r => r.resolvedOwner.length === 0).map(r => `${r.path}:${r.line} ${r.member}`).join('\n') || '(none)');
console.log('\n--- CONFIRMED-DEAD (no owner-qualified call anywhere) ---');
out.filter(r => r.verdict === 'CONFIRMED-DEAD').forEach(r => console.log(`  ${r.path}:${r.line}  ${r.member}  owner=[${r.resolvedOwner.join('|')}]`));
console.log('\n--- REDUNDANT-EXPORT (used only inside its own class/file) ---');
out.filter(r => r.verdict === 'REDUNDANT-EXPORT').forEach(r => console.log(`  ${r.path}:${r.line}  ${r.member}  owner=[${r.resolvedOwner.join('|')}]  loose=${r.looseInternal.length}`));
console.log('\n--- FALSE-POSITIVE (called as Owner.member) ---');
out.filter(r => r.verdict === 'FALSE-POSITIVE').forEach(r => console.log(`  ${r.path}:${r.line}  ${r.member}  owner=[${r.resolvedOwner.join('|')}]  <- ${r.evidence.join(' ')}`));

fs.writeFileSync(path.join(ROOT, 'audit/fallow-tools/class-member-verdicts.json'), JSON.stringify(out, null, 1));
