// STRICT verifier: module-scoped resolution for exports/types/enums, owner-scoped for class members.
// A consumer of `X` from module M must reach M through an import specifier that resolves to M.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = '/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter';
const SNAPSHOT = process.argv[2] || 'audit/fallow-tools/snapshot.json';
const j = JSON.parse(fs.readFileSync(path.join(ROOT, SNAPSHOT), 'utf8'));
const chk = j.check;

const NOISE = /^(server\/graphify-out\/|server\/client\/dist\/|coverage\/|build\/|graphify-out\/|node_modules\/|server\/node_modules\/|audit\/)/;
const files = execFileSync('git', ['ls-files'], { cwd: ROOT, encoding: 'utf8' })
  .split('\n').filter(Boolean).filter(f => !NOISE.test(f) && /\.(ts|tsx|js|jsx|mjs|cjs)$/.test(f));

const corpus = [];
for (const f of files) { try { corpus.push({ file: f, text: fs.readFileSync(path.join(ROOT, f), 'utf8') }); } catch {} }
const byFile = new Map(corpus.map(c => [c.file, c]));

const ESC = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const modKey = (p) => p.replace(/\.tsx?$/, '').replace(/\.jsx?$/, '');

// ---- index every import site: resolved module -> { named: Map(sym->sites), ns: Map(localAlias->sites) } ----
const namedIdx = new Map();   // modKey -> Map(symbol -> [sites])
const nsIdx = new Map();      // modKey -> Map(localAlias -> [sites])
function addNamed(mk, sym, site) { if (!namedIdx.has(mk)) namedIdx.set(mk, new Map()); const m = namedIdx.get(mk); if (!m.has(sym)) m.set(sym, []); m.get(sym).push(site); }
function addNs(mk, alias, site) { if (!nsIdx.has(mk)) nsIdx.set(mk, new Map()); const m = nsIdx.get(mk); if (!m.has(alias)) m.set(alias, []); m.get(alias).push(site); }

const importNamed = /import\s+(?:type\s+)?\{([^}]*)\}\s*from\s*['"]([^'"]+)['"]/g;
const importNs = /import\s+(?:type\s+)?\*\s+as\s+(\w+)\s+from\s*['"]([^'"]+)['"]/g;
const importDefault = /import\s+(\w+)\s*(?:,\s*\{([^}]*)\})?\s*from\s*['"]([^'"]+)['"]/g;
const requireNs = /(?:const|let|var)\s+(\w+)\s*=\s*require\(\s*['"]([^'"]+)['"]\s*\)/g;
const awaitImport = /await\s+import\(\s*['"]([^'"]+)['"]\s*\)/g;

for (const { file, text } of corpus) {
  const dir = path.dirname(file);
  const resolve = (spec) => {
    if (!spec.startsWith('.')) return null;
    let abs = path.normalize(path.join(dir, spec));
    const cand = [abs + '.ts', abs + '.tsx', abs + '.js', abs + '.jsx', abs + '.cjs', abs + '.mjs', abs + '/index.ts'];
    for (const c of cand) if (byFile.has(c)) return modKey(c);
    return modKey(abs);
  };
  let m;
  while ((m = importNamed.exec(text))) {
    const mk = resolve(m[2]); if (!mk) continue;
    const site = `${file}:${text.slice(0, m.index).split('\n').length}`;
    for (const raw of m[1].split(',')) {
      const t = raw.trim(); if (!t) continue;
      const sym = t.split(/\s+as\s+/)[0].trim().replace(/^type\s+/, '');
      addNamed(mk, sym, site);
    }
  }
  while ((m = importNs.exec(text))) { const mk = resolve(m[2]); if (mk) addNs(mk, m[1], `${file}:${text.slice(0, m.index).split('\n').length}`); }
  while ((m = importDefault.exec(text))) {
    const mk = resolve(m[3]); if (!mk) continue;
    const site = `${file}:${text.slice(0, m.index).split('\n').length}`;
    addNs(mk, m[1], site);
    if (m[2]) for (const raw of m[2].split(',')) { const t = raw.trim(); if (t) addNamed(mk, t.split(/\s+as\s+/)[0].trim().replace(/^type\s+/, ''), site); }
  }
  while ((m = requireNs.exec(text))) { const mk = resolve(m[2]); if (mk) addNs(mk, m[1], `${file}:${text.slice(0, m.index).split('\n').length}`); }
  while ((m = awaitImport.exec(text))) { const mk = resolve(m[1]); if (mk) addNs(mk, '*dynamic*', `${file}:${text.slice(0, m.index).split('\n').length}`); }
}

// default-export object members: module -> Set(member)
const defObjMembers = new Map();
for (const { file, text } of corpus) {
  const i = text.indexOf('export default {');
  if (i < 0) continue;
  let depth = 0, end = i;
  for (let k = i; k < text.length; k++) { if (text[k] === '{') depth++; else if (text[k] === '}') { depth--; if (depth === 0) { end = k; break; } } }
  const body = text.slice(i, end + 1);
  const members = new Set();
  for (const mm of body.matchAll(/^\s*([A-Za-z_$][\w$]*)\s*[,:}]/gm)) members.add(mm[1]);
  defObjMembers.set(modKey(file), members);
}

// is symbol referenced in a file other than the declaring one, as a member of a namespace import of that module?
function namespaceUses(declPath, sym) {
  const mk = modKey(declPath);
  const sites = [];
  for (const { file, text } of corpus) {
    if (file === declPath) continue;
    const aliases = [];
    const re = new RegExp(`import\\s+(\\w+)[^;]*from\\s*['"][^'"]*${ESC(path.basename(mk))}['"]`, 'g');
    let mm; while ((mm = re.exec(text))) aliases.push(mm[1]);
    const re2 = new RegExp(`import\\s*\\{[^}]*\\b${ESC(sym)}\\b[^}]*\\}\\s*from\\s*['"][^'"]*${ESC(path.basename(mk))}['"]`, 'g');
    const hasNamed = re2.test(text);
    for (const a of aliases) {
      const ar = new RegExp(`\\b${ESC(a)}\\s*\\.\\s*${ESC(sym)}\\b`);
      text.split('\n').forEach((line, i) => { if (ar.test(line)) sites.push(`${file}:${i + 1}`); });
    }
    if (hasNamed) sites.push(`${file}:(named import)`);
  }
  return sites;
}

function ownFileRefs(declPath, sym) {
  const c = byFile.get(declPath); if (!c) return 0;
  const re = new RegExp(`\\b${ESC(sym)}\\b`);
  const declRe = new RegExp(`^\\s*(?:export\\s+)?(?:default\\s+)?(?:async\\s+)?(?:function\\s*\\*?|const|let|var|class|interface|type|enum|abstract\\s+class)\\s+${ESC(sym)}\\b`);
  let n = 0;
  c.text.split('\n').forEach((l) => { if (re.test(l) && !declRe.test(l.trim())) n++; });
  return n;
}

function verdictFor(declPath, sym) {
  const mk = modKey(declPath);
  const named = namedIdx.get(mk)?.get(sym) || [];
  if (named.length) return { v: 'FALSE-POSITIVE', why: `imported by name at ${named.slice(0, 2).join(', ')}` };
  const ns = namespaceUses(declPath, sym);
  if (ns.length) return { v: 'FALSE-POSITIVE', why: `used via namespace member access at ${ns.slice(0, 2).join(', ')}` };
  const own = ownFileRefs(declPath, sym);
  if (own > 0) return { v: 'REDUNDANT-EXPORT', why: `referenced ${own}x inside its own module only` };
  return { v: 'CONFIRMED-DEAD', why: 'no consumer anywhere' };
}

const cats = {
  exports: chk.unused_exports.map(f => ({ path: f.path, sym: f.export_name, line: f.line })),
  types: chk.unused_types.map(f => ({ path: f.path, sym: f.export_name, line: f.line })),
  enums: chk.unused_enum_members.map(f => ({ path: f.path, sym: f.member_name, line: f.line, parent: f.parent_name })),
};
const results = {};
for (const [cat, list] of Object.entries(cats)) {
  results[cat] = list.map(it => ({ ...it, ...verdictFor(it.path, it.sym) }));
}
fs.writeFileSync(path.join(ROOT, 'audit/fallow-tools/strict-verdicts.json'), JSON.stringify(results, null, 1));

for (const [cat, list] of Object.entries(results)) {
  const t = list.reduce((a, r) => (a[r.v] = (a[r.v] || 0) + 1, a), {});
  console.log(`\n##### ${cat}: ${list.length}  ${JSON.stringify(t)}`);
  for (const v of ['CONFIRMED-DEAD', 'REDUNDANT-EXPORT', 'FALSE-POSITIVE']) {
    const g = list.filter(r => r.v === v);
    if (!g.length) continue;
    console.log(`  -- ${v} (${g.length}) --`);
    g.forEach(r => console.log(`     ${r.path}:${r.line}  ${r.sym}  | ${r.why}`));
  }
}
