// Remove dead declarations safely: locate the declaration, absorb its leading
// doc comment, brace/paren-match to its end, and cut the range.
import fs from 'node:fs';
import path from 'node:path';

const ROOT = '/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter';
const SERVER = path.join(ROOT, 'server');
const DRY = process.argv.includes('--dry-run');

const ESC = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// target: [fileRelativeToServer, symbol, kind]
// kind: 'function' | 'const' | 'type' | 'interface' | 'classmethod'
const TARGETS = JSON.parse(fs.readFileSync(path.join(ROOT, 'audit/fallow-tools/removal-targets.json'), 'utf8'));

function findDeclaration(lines, sym, kind) {
  const declRe = new RegExp(
    kind === 'classmethod'
      ? `^\\s*(?:(?:public|private|protected|static|readonly|async|get|set)\\s+)*${ESC(sym)}\\s*[(<]`
      : `^\\s*export\\s+(?:default\\s+)?(?:async\\s+)?(?:function\\s*\\*?|const|let|var|class|interface|type|enum|abstract\\s+class)\\s+${ESC(sym)}\\b`
  );
  for (let i = 0; i < lines.length; i++) {
    if (!declRe.test(lines[i])) continue;
    // `export const X = (...) => expr;` and `export type X = 'a' | 'b';`
    // are statements: end at the first `;` at depth 0.
    // Statement forms end at the first `;` at depth 0; block forms (function,
    // class, interface, object type) are brace-matched.
    const isVarDecl = /^export\s+(const|let|var)\b/.test(lines[i]);
    const isTypeAlias = /^export\s+type\b/.test(lines[i]);
    const isStatement = isVarDecl || (isTypeAlias && !lines[i].includes('{'));
    if (isStatement) {
      let depth = 0, j = i, ended = false;
      for (; j < lines.length; j++) {
        for (const ch of lines[j]) {
          if ('([{'.includes(ch)) depth++;
          else if (')]}'.includes(ch)) depth--;
          else if (ch === ';' && depth === 0) { ended = true; break; }
        }
        if (ended) break;
      }
      if (!ended) throw new Error(`no end found for statement ${sym} in ${i + 1}`);
      return { start: i, end: j };
    }
    // Block form. Track a brace stack; the body `{` is the first brace pushed
    // at paren-depth 0, so an inline object type in the parameter list is not
    // mistaken for the body.
    const stack = [];
    let paren = 0, bodyDepth = -1, j = i;
    for (; j < lines.length; j++) {
      for (const ch of lines[j]) {
        if (ch === '(') paren++;
        else if (ch === ')') paren--;
        else if (ch === '{') {
          stack.push(paren);
          if (bodyDepth < 0 && paren === 0) bodyDepth = stack.length;
        } else if (ch === '}' && stack.length) {
          const wasBody = stack.length === bodyDepth;
          stack.pop();
          if (wasBody && bodyDepth >= 0) { bodyDepth = -2; }
        }
      }
      if (bodyDepth === -2) break;
      if (stack.length === 0 && bodyDepth < 0 && /;\s*$/.test(lines[j]) && j > i) break;
    }
    if (bodyDepth !== -2) throw new Error(`no body found for ${sym} at ${i + 1}`);
    return { start: i, end: j };
  }
  return null;
}

function absorbDocComment(lines, start) {
  let s = start;
  // walk back over a contiguous /** ... */ or // block immediately above
  let j = start - 1;
  if (j >= 0 && /^\s*\/\*\*/.test(lines[j])) {
    while (j >= 0 && !/\*\/\s*$/.test(lines[j])) j--;
    s = Math.max(0, j);
  } else {
    let k = start - 1;
    while (k >= 0 && /^\s*\/\//.test(lines[k])) k--;
    s = k + 1;
  }
  // do not absorb a blank separator that is followed by another comment block
  return s;
}

const byFile = new Map();
for (const t of TARGETS) {
  if (!byFile.has(t.file)) byFile.set(t.file, []);
  byFile.get(t.file).push(t);
}

let totalRemoved = 0;
const report = [];

for (const [file, targets] of byFile) {
  const abs = path.join(SERVER, file);
  let lines = fs.readFileSync(abs, 'utf8').split('\n');
  // process bottom-up so earlier line numbers stay valid
  const resolved = [];
  for (const t of targets) {
    const d = findDeclaration(lines, t.sym, t.kind);
    if (!d) { report.push(`  !! NOT FOUND  ${file}  ${t.sym} (${t.kind})`); continue; }
    const s = absorbDocComment(lines, d.start);
    resolved.push({ ...t, from: s, to: d.end, snippet: lines.slice(s, d.end + 1).join('\n') });
  }
  resolved.sort((a, b) => b.from - a.from);
  // overlap guard: no two removal ranges may intersect
  for (let i = 0; i < resolved.length - 1; i++) {
    const cur = resolved[i], prev = resolved[i + 1];
    if (prev.to >= cur.from) {
      throw new Error(`OVERLAP in ${file}: ${cur.sym} [${cur.from + 1}-${cur.to + 1}] vs ${prev.sym} [${prev.from + 1}-${prev.to + 1}]`);
    }
  }
  for (const r of resolved) {
    lines.splice(r.from, r.to - r.from + 1);
    totalRemoved++;
    report.push(`  - ${file}  ${r.sym}  lines ${r.from + 1}-${r.to + 1}`);
  }
  // collapse 3+ consecutive blank lines to 1
  lines = lines.join('\n').replace(/\n{3,}/g, '\n\n').split('\n');
  if (!DRY) fs.writeFileSync(abs, lines.join('\n'));
}

console.log(DRY ? '=== DRY RUN ===' : '=== APPLIED ===');
console.log(report.join('\n'));
console.log(`\n${totalRemoved} declarations removed across ${byFile.size} files.`);
