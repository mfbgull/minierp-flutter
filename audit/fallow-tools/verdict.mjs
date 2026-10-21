// FINAL per-finding verdict for fallow dead-code findings.
// Rules:
//  - TS/JS corpus only (Dart symbols are unrelated to server TS types)
//  - class members matched as <OwnerClass>.<member>, owner resolved from the file
//  - internal (same-file) references separated from external consumers
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = '/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter';
const SNAPSHOT = process.argv[2] || 'audit/fallow-tools/snapshot.json';
const j = JSON.parse(fs.readFileSync(SNAPSHOT, 'utf8'));
const chk = j.check;

const NOISE = /^(server\/graphify-out\/|server\/client\/dist\/|coverage\/|build\/|graphify-out\/|node_modules\/|server\/node_modules\/|audit\/)/;
const files = execFileSync('git', ['ls-files'], { cwd: ROOT, encoding: 'utf8' })
  .split('\n').filter(Boolean)
  .filter((f) => !NOISE.test(f))
  .filter((f) => /\.(ts|tsx|js|jsx|mjs|cjs)$/.test(f));

const corpus = [];
for (const f of files) {
  let text;
  try { text = fs.readFileSync(path.join(ROOT, f), 'utf8'); } catch { continue; }
  corpus.push({ file: f, lines: text.split('\n'), text });
}
const byFile = new Map(corpus.map((c) => [c.file, c]));

const ESC = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function declOrExportList(text, name) {
  const t = text.trim();
  const n = ESC(name);
  return (
    new RegExp(`^export\\s+(default\\s+)?(async\\s+)?(function\\s*\\*?|const|let|var|class|interface|type|enum|abstract\\s+class)\\s+${n}\\b`).test(t) ||
    new RegExp(`^export\\s*\\{`).test(t) ||
    new RegExp(`^export\\s+type\\s*\\{`).test(t) ||
    new RegExp(`^\\s*${n}\\s*[},]?\\s*$`).test(t) ||
    new RegExp(`^\\s*${n}\\s*[:,]\\s*$`).test(t) ||
    new RegExp(`^\\s*${n}\\s*=\\s*'[^']*',?\\s*$`).test(t) // enum member initializer
  );
}

// Resolve the real owner class name for a file (fallow reports "default" as parent).
function ownerNames(file) {
  const c = byFile.get(file);
  if (!c) return [];
  const names = new Set();
  for (const m of c.text.matchAll(/^\s*(?:export\s+)?(?:abstract\s+)?class\s+([A-Za-z_$][\w$]*)/gm)) names.add(m[1]);
  for (const m of c.text.matchAll(/^\s*export\s+default\s+([A-Za-z_$][\w$]*)\s*;/gm)) names.add(m[1]);
  for (const m of c.text.matchAll(/^\s*export\s+(?:const|let)\s+([A-Za-z_$][\w$]*)\s*[:=]/gm)) names.add(m[1]);
  return [...names];
}

function scan(declPath, name, owner) {
  const re = new RegExp(`\\b${ESC(name)}\\b`);
  const internal = [];
  const external = [];
  const qualifiedRe = owner && owner.length
    ? new RegExp(`\\b(${owner.map(ESC).join('|')})\\s*\\.\\s*${ESC(name)}\\b`)
    : null;
  for (const { file, lines } of corpus) {
    const inDecl = file === declPath;
    for (let i = 0; i < lines.length; i++) {
      const text = lines[i];
      if (!re.test(text)) continue;
      if (inDecl && declOrExportList(text, name)) continue;
      if (inDecl) { internal.push({ file, line: i + 1, text: text.trim() }); continue; }
      const rec = { file, line: i + 1, text: text.trim() };
      if (qualifiedRe && qualifiedRe.test(text)) rec.rel = 'qualified-call';
      else if (new RegExp(`\\.\\s*${ESC(name)}\\b`).test(text)) rec.rel = 'member-access';
      else rec.rel = 'named-ref';
      external.push(rec);
    }
  }
  return { internal, external };
}

function verdictFor(item, sc) {
  const { external, internal } = sc;
  if (item.sym === 'default') {
    return { v: 'FALSE-POSITIVE', why: 'fallow reports the `export default` keyword itself as an unused export named "default"' };
  }
  if (external.length === 0 && internal.length === 0) {
    return { v: 'CONFIRMED-DEAD', why: 'zero references anywhere in the TS/JS tree outside the declaration' };
  }
  if (external.length === 0) {
    return { v: 'REDUNDANT-NAMED-EXPORT', why: `used only inside its own module (${internal.length} internal refs) - the export keyword is unnecessary, the code is live` };
  }
  const rels = [...new Set(external.map((e) => e.rel))];
  if (rels.includes('qualified-call') || rels.includes('member-access')) {
    return { v: 'FALSE-POSITIVE', why: `live - consumed via ${rels.join(' + ')}` };
  }
  return { v: 'FALSE-POSITIVE', why: `live - referenced by name (${rels.join(' + ')})` };
}

const cats = {
  exports: chk.unused_exports.map((f) => ({ path: f.path, sym: f.export_name, kind: 'export', line: f.line })),
  types: chk.unused_types.map((f) => ({ path: f.path, sym: f.export_name, kind: 'type_export', line: f.line })),
  enums: chk.unused_enum_members.map((f) => ({ path: f.path, sym: f.member_name, kind: 'enum_member', line: f.line, parent: f.parent_name })),
  class_members: chk.unused_class_members.map((f) => ({ path: f.path, sym: f.member_name, kind: 'class_member', line: f.line, parent: f.parent_name })),
};

const results = {};
for (const [cat, list] of Object.entries(cats)) {
  results[cat] = list.map((item) => {
    const owner = item.kind === 'class_member' ? ownerNames(item.path) : [];
    const sc = scan(item.path, item.sym, owner);
    const vd = verdictFor(item, sc);
    return { ...item, owner, verdict: vd.v, why: vd.why, external: sc.external, internalCount: sc.internal.length };
  });
}

fs.writeFileSync('audit/fallow-tools/verdicts.json', JSON.stringify(results, null, 1));

for (const [cat, list] of Object.entries(results)) {
  const tally = {};
  for (const r of list) tally[r.verdict] = (tally[r.verdict] || 0) + 1;
  console.log(`\n########## ${cat}: ${list.length} flagged ##########  ${JSON.stringify(tally)}`);
  for (const v of ['CONFIRMED-DEAD', 'REDUNDANT-NAMED-EXPORT', 'FALSE-POSITIVE']) {
    const g = list.filter((r) => r.verdict === v);
    if (!g.length) continue;
    console.log(`  -- ${v} (${g.length}) --`);
    for (const r of g) {
      const ex = r.external.slice(0, 2).map((c) => `${c.file}:${c.line}`).join(' ');
      console.log(`     ${r.path}:${r.line}  ${r.sym}${r.owner?.length ? ` [${r.owner.join('|')}]` : ''}  ${ex ? '| ' + ex : '| (none)'}`);
    }
  }
}
