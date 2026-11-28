/**
 * Issue #36 - idempotency route inventory.
 *
 * Joins each mount in src/app.ts with the mutating routes declared in
 * src/routes/*.ts, then reports whether any test under src/__tests__
 * calls that route path. The output is the raw evidence for
 * docs/IDEMPOTENCY-INVENTORY.md. Classification (keyed / state guard)
 * stays manual: a path match does not prove what the test asserts.
 *
 * Usage: node server/scripts/idempotency-inventory.js
 */
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..', 'src');
const appSource = fs.readFileSync(path.join(root, 'app.ts'), 'utf8');

const imports = {};
for (const match of appSource.matchAll(/import\s+(\w+)\s+from\s+'\.\/routes\/(\w+)'/g)) {
  imports[match[1]] = match[2];
}

const mounts = [];
for (const match of appSource.matchAll(/app\.use\('([^']+)',\s*(\w+)\)/g)) {
  if (imports[match[2]]) mounts.push({ prefix: match[1], file: imports[match[2]] });
}

const testSource = fs
  .readdirSync(path.join(root, '__tests__'))
  .filter((file) => file.endsWith('.test.ts'))
  .map((file) => fs.readFileSync(path.join(root, '__tests__', file), 'utf8'))
  .join('\n');

function escapeRegExp(value) {
  return value.replace(/[.*+?^$()|[\]\\]/g, '\\$&');
}

function routePattern(fullPath) {
  return escapeRegExp(fullPath)
    .split('/:')
    .map((part, index) => (index === 0 ? part : '/[^/]+' + part.slice(part.indexOf('/'))))
    .join('');
}

const routes = [];
for (const mount of mounts) {
  const source = fs.readFileSync(path.join(root, 'routes', mount.file + '.ts'), 'utf8');
  for (const match of source.matchAll(/router\.(post|put|patch|delete)\(\s*'([^']+)'/g)) {
    const fullPath = (mount.prefix + match[2]).replace(/\/+$/, '') || mount.prefix;
    let tested = false;
    try {
      tested = new RegExp(routePattern(fullPath)).test(testSource);
    } catch {
      tested = testSource.includes(fullPath.split('/:')[0]);
    }
    routes.push({ method: match[1].toUpperCase(), path: fullPath, file: mount.file, tested });
  }
}

routes.sort((a, b) => a.path.localeCompare(b.path));
for (const route of routes) {
  console.log([route.method, route.path, route.tested ? 'REFERENCED' : 'UNVERIFIED', route.file].join('\t'));
}
const unverified = routes.filter((route) => !route.tested).length;
console.log(`\nTOTAL\t${routes.length}\tUNVERIFIED\t${unverified}`);
