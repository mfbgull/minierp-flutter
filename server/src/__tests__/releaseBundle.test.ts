import fs from 'fs';
import path from 'path';

const REPO_ROOT = path.join(__dirname, '..', '..', '..');
const WORKFLOW = path.join(REPO_ROOT, '.github', 'workflows', 'release.yml');

const yaml = fs.readFileSync(WORKFLOW, 'utf8');

function indexOfStep(name: string): number {
  const i = yaml.indexOf(`- name: ${name}`);
  expect(i).toBeGreaterThan(-1);
  return i;
}

describe('release bundle integrity (H13)', () => {
  it('ships the release workflow', () => {
    expect(fs.existsSync(WORKFLOW)).toBe(true);
  });

  it('builds the server before packaging the separate-install bundle', () => {
    const build = indexOfStep('Build server and create .run installer');
    const pack = indexOfStep('Package server bundle for separate-install platforms');
    expect(build).toBeLessThan(pack);
    expect(yaml.slice(build, pack)).toMatch(/cd server && npm run build/);
  });

  it('stages the lockfile so the bundle can be installed with npm ci', () => {
    const pack = indexOfStep('Package server bundle for separate-install platforms');
    const end = indexOfStep('Verify server bundle contents');
    const step = yaml.slice(pack, end);
    expect(step).toMatch(/cp server\/package\.json server\/package-lock\.json/);
  });

  it('instructs the user to install with npm ci, which requires that lockfile', () => {
    const start = yaml.indexOf('cat > "$STAGE/INSTALL.txt" <<\'EOF\'');
    expect(start).toBeGreaterThan(-1);
    const heredoc = yaml.slice(start, yaml.indexOf('\nEOF', start));
    expect(heredoc).toMatch(/npm ci --omit=dev/);
  });

  it('writes INSTALL.txt into the bundle', () => {
    const pack = indexOfStep('Package server bundle for separate-install platforms');
    const end = indexOfStep('Verify server bundle contents');
    const step = yaml.slice(pack, end);
    expect(step).toMatch(/cat > "\$STAGE\/INSTALL\.txt"/);
  });

  it('verifies the packaged zip actually contains the lockfile and INSTALL.txt', () => {
    const verify = indexOfStep('Verify server bundle contents');
    const step = yaml.slice(verify, verify + 1200);
    expect(step).toMatch(/unzip -l .*MiniERP-\$\{VERSION\}-server\.zip/);
    expect(step).toMatch(/grep -q "server\/package-lock\.json"/);
    expect(step).toMatch(/grep -q "INSTALL\.txt"/);
  });

  it('uploads the server bundle as a release artifact', () => {
    const verify = indexOfStep('Upload server bundle artifact');
    expect(verify).toBeGreaterThan(-1);
    const step = yaml.slice(verify, verify + 600);
    expect(step).toMatch(/server\.zip/);
  });
});