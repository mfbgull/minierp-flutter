const fs = require('node:fs');
const path = require('node:path');
const { fileURLToPath } = require('node:url');

const root = path.resolve(__dirname, '../../..');
const { createCoverageMap } = require('istanbul-lib-coverage');
const v8ToIstanbul = require('v8-to-istanbul');
let compiler;

function isProjectScript(filename) {
  const relative = path.relative(root, filename).split(path.sep).join('/');
  return relative.startsWith('scripts/') || relative.startsWith('server/scripts/');
}

function mappedScriptSource(filename, cachedMap, capturedAt) {
  const source = fs.readFileSync(filename, 'utf8');
  if (!cachedMap) {
    if (filename.endsWith('.ts')) return undefined;
    if (fs.statSync(filename).mtimeMs > capturedAt) return undefined;
    return { source };
  }
  const originals = cachedMap.data?.sourcesContent;
  if (originals?.length !== 1 || originals[0] !== source) return undefined;
  compiler ??= require('ts-node').create({
    project: path.join(root, 'server/tsconfig.test.json'),
    transpileOnly: true,
  });
  const generated = compiler.compile(source, filename);
  const lengths = generated.split('\n').map(line => line.length);
  if (lengths.length !== cachedMap.lineLengths.length
      || lengths.some((length, index) => length !== cachedMap.lineLengths[index])) {
    throw new Error(`Compiled coverage offsets do not match ${filename}`);
  }
  return { source: generated, sourceMap: { sourcemap: cachedMap.data } };
}

async function mergeCapture(coverage, capturePath, alreadyInstrumented) {
  const capture = JSON.parse(fs.readFileSync(capturePath, 'utf8'));
  const capturedAt = fs.statSync(capturePath).mtimeMs;
  const converted = [];
  const stale = [];
  for (const script of capture.result) {
    if (!script.url.startsWith('file:')) continue;
    const filename = fileURLToPath(script.url);
    if (!isProjectScript(filename) || alreadyInstrumented.has(filename)) continue;
    const source = mappedScriptSource(filename, capture['source-map-cache']?.[script.url], capturedAt);
    if (!source) {
      stale.push(filename);
      continue;
    }
    const converter = v8ToIstanbul(filename, 0, source);
    await converter.load();
    converter.applyCoverage(script.functions);
    coverage.merge(converter.toIstanbul());
    converted.push(filename);
  }
  return { converted, stale };
}

async function mergeFallowCoverage(istanbulFile, v8Directories, outputFile) {
  const coverage = createCoverageMap(JSON.parse(fs.readFileSync(istanbulFile, 'utf8')));
  const alreadyInstrumented = new Set(coverage.files());
  const converted = new Set();
  const stale = new Set();
  for (const directory of v8Directories) {
    for (const filename of fs.readdirSync(directory).filter(name => name.endsWith('.json')).sort()) {
      const result = await mergeCapture(coverage, path.join(directory, filename), alreadyInstrumented);
      for (const file of result.converted) converted.add(file);
      for (const file of result.stale) stale.add(file);
    }
  }
  fs.mkdirSync(path.dirname(outputFile), { recursive: true });
  fs.writeFileSync(outputFile, JSON.stringify(coverage.toJSON()));
  return { outputFile, files: coverage.files().length, converted: [...converted].sort(), stale: [...stale].sort() };
}

if (require.main === module) {
  const [istanbulFile, outputFile, ...v8Directories] = process.argv.slice(2);
  if (!istanbulFile || !outputFile || v8Directories.length === 0) {
    console.error('Usage: node server/scripts/lib/merge-fallow-coverage.cjs <istanbul.json> <output.json> <v8-directory> [...]');
    process.exitCode = 2;
  } else {
    mergeFallowCoverage(istanbulFile, v8Directories, outputFile)
      .then(result => console.log(JSON.stringify(result)))
      .catch(error => { console.error(error.message); process.exitCode = 1; });
  }
}

module.exports = { mergeFallowCoverage };
