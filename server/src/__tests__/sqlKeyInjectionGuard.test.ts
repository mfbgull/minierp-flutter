import fs from 'fs';
import path from 'path';

/**
 * SEC-001 / SEC-002 — structural guards against request keys reaching SQL.
 *
 * The forecast model-config defect was not exotic: a service built a SET clause
 * from `Object.entries(config)` while the route validator was
 * `z.object({}).passthrough()`. Seven sibling schemas are still passthrough
 * catch-alls bound to ~48 routes, so the *shape* of the bug can recur even
 * though no other site currently splices.
 *
 * These guards fail on the pattern, not on one call site, so a new instance is
 * caught before it is exploited.
 */

const SRC = path.join(__dirname, '..');
const SCAN_DIRS = ['services', 'models', 'controllers', 'middleware'];
const SCAN_EXT = /\.ts$/;

function walk(dir: string): string[] {
  const out: string[] = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === '__tests__') continue;
      out.push(...walk(full));
    } else if (SCAN_EXT.test(entry.name)) {
      out.push(full);
    }
  }
  return out;
}

const files = SCAN_DIRS.flatMap((d) => {
  const dir = path.join(SRC, d);
  return fs.existsSync(dir) ? walk(dir) : [];
});

describe('SEC-002 — request keys never reach a SQL string', () => {
  it('no SQL statement is built from Object.keys/entries of a caller-supplied object', () => {
    const offenders: string[] = [];

    for (const file of files) {
      const text = fs.readFileSync(file, 'utf8');
      const lines = text.split('\n');

      lines.forEach((line, i) => {
        if (!/Object\.(keys|entries)\s*\(/.test(line)) return;
        // The variable must flow into a template literal that is prepared.
        const window = lines.slice(i, i + 12).join('\n');
        const producesKeys = /\$\{[^}]*\b(keys|columns|fields|cols)\b[^}]*\}/.test(window);
        const reachesPrepare = /prepare\(\s*`/.test(window);
        if (producesKeys && reachesPrepare) {
          offenders.push(
            `${path.relative(SRC, file)}:${i + 1}  ${line.trim().slice(0, 70)}`
          );
        }
      });
    }

    expect(offenders).toEqual([]);
  });

  it('the forecast model-config allowlist is the only column source', () => {
    const text = fs.readFileSync(path.join(SRC, 'services', 'forecastService.ts'), 'utf8');
    const body = text.slice(text.indexOf('export function setModelConfig'));

    expect(body).toContain('MODEL_CONFIG_COLUMNS');
    expect(body).not.toContain('Object.entries(config)');
    expect(body).not.toContain('Object.keys(config)');
  });
});

describe('SEC-002 — passthrough catch-alls are an inventory, not a silent default', () => {
  it('every remaining z.object({}).passthrough() schema is listed in KNOWN_PASSTHROUGH', () => {
    const validation = fs.readFileSync(path.join(SRC, 'middleware', 'validation.ts'), 'utf8');
    const declared = [...validation.matchAll(/^\s{2}(\w+):\s*z\.object\(\{\}\)\.passthrough\(\)/gm)].map((m) => m[1]);

    // Each of these accepts any shape. That is tolerable only while the handler
    // filters explicitly, so the set is pinned here: adding one without
    // reviewing the handler fails this test.
    const KNOWN_PASSTHROUGH = [
      'object',
      'mobileDraft',
      'dashboardLayoutCreate',
      'preferencesUpdate',
      'integrationSettings',
      'forecastOverride',
      'seasonalEvent',
    ];

    expect(declared.sort()).toEqual(KNOWN_PASSTHROUGH.slice().sort());
  });

  it('no schema is passthrough AND optional-with-nothing — they must at least be enumerable', () => {
    const validation = fs.readFileSync(path.join(SRC, 'middleware', 'validation.ts'), 'utf8');
    const offenders = [...validation.matchAll(/^\s{2}(\w+):\s*(z\.object\(\{\}\)\.passthrough\(\))/gm)]
      .map((m) => m[1])
      .filter((name) => !KNOWN_PASSTHROUGH.includes(name));

    expect(offenders).toEqual([]);
  });
});

const KNOWN_PASSTHROUGH: string[] = [
  'object',
  'mobileDraft',
  'dashboardLayoutCreate',
  'preferencesUpdate',
  'integrationSettings',
  'forecastOverride',
  'seasonalEvent',
];