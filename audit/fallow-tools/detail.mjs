import fs from 'node:fs';
const v = JSON.parse(fs.readFileSync('audit/fallow-tools/verdicts.json', 'utf8'));
const pick = process.argv[2];
const sym = process.argv[3];
for (const [cat, list] of Object.entries(v)) {
  for (const r of list) {
    if (cat !== pick) continue;
    if (sym && r.sym !== sym) continue;
    console.log(`\n### ${cat} ${r.path}:${r.line} ${r.sym}  -> ${r.verdict}`);
    console.log(`    why: ${r.why}`);
    console.log(`    consumers (${r.consumers.length}):`);
    for (const c of r.consumers.slice(0, 12)) {
      console.log(`      ${c.file}:${c.line} [${c.rel}] ${c.text.slice(0, 130)}`);
    }
  }
}
