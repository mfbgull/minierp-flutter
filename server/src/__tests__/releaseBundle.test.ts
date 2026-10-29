import fs from 'fs';
import path from 'path';

const REPO_ROOT = path.join(__dirname, '..', '..', '..');
const WORKFLOW = path.join(REPO_ROOT, '.github', 'workflows', 'release.yml');

const yaml = fs.readFileSync(WORKFLOW, 'utf8');

/** Extracts a top-level job block (job keys are indented two spaces). */
function job(name: string): string {
  const marker = `\n  ${name}:\n`;
  const start = yaml.indexOf(marker);
  expect(start).toBeGreaterThan(-1);
  const rest = yaml.slice(start + marker.length);
  const next = rest.search(/\n {2}[a-z][a-z0-9-]*:\n/);
  return next === -1 ? rest : rest.slice(0, next);
}

const PACKAGING_JOBS = ['build-linux', 'build-windows', 'build-macos'];

describe('release bundle integrity (self-contained artifacts)', () => {
  it('ships the release workflow', () => {
    expect(fs.existsSync(WORKFLOW)).toBe(true);
  });

  it('builds the server once on Linux and shares it as an artifact', () => {
    const server = job('build-server');
    expect(server).toMatch(/runs-on: ubuntu-22\.04/);
    expect(server).toMatch(/npm ci/);
    expect(server).toMatch(/npm run build/);
    expect(server).toMatch(/name: server-dist/);
    // A payload without migrations cannot create the database on first boot.
    expect(server).toMatch(/dist\/src\/migrations/);
  });

  it.each(PACKAGING_JOBS)('%s consumes the shared server build', (name) => {
    const block = job(name);
    // Without the dependency the job starts in parallel and the artifact
    // download fails before the producer has uploaded it.
    expect(block).toMatch(/needs: build-server/);
    expect(block).toMatch(/name: server-dist/);
    expect(block).toMatch(/tool\/stage-server\.mjs/);
  });

  it.each(PACKAGING_JOBS)('%s smoke-tests its payload before upload', (name) => {
    expect(job(name)).toMatch(/tool\/smoke-server\.mjs/);
  });

  it('installs the bundled server beside the Debian client', () => {
    const linux = job('build-linux');
    expect(linux).toMatch(
      /cp -a build\/server-payload pkg\/usr\/lib\/minierp_app\/server/,
    );
    expect(linux).toMatch(/lib\/minierp_app\/server\/dist\/server\.js/);
    expect(linux).toMatch(/lib\/minierp_app\/server\/runtime\/node/);
  });

  it('embeds the bundled server in the AppImage', () => {
    const linux = job('build-linux');
    expect(linux).toMatch(
      /cp -a build\/server-payload AppDir\/usr\/lib\/minierp_app\/server/,
    );
    expect(linux).toMatch(/squashfs-root\/usr\/lib\/minierp_app\/server\/runtime\/node/);
  });

  it('packages the .run installer from the same staged payload', () => {
    const linux = job('build-linux');
    expect(linux).toMatch(/tool\/make_linux_setup\.sh --no-build --fresh/);
    expect(linux).toMatch(/linux-x64\.run/);
  });

  it('frees each payload copy before the next Linux package', () => {
    const linux = job('build-linux');
    // Three copies of the server payload otherwise exhaust the runner disk.
    expect(linux).toMatch(/rm -rf build\/setup-stage build\/setup-payload\.tar\.gz/);
    expect(linux).toMatch(/rm -rf pkg/);
    expect(linux).toMatch(/rm -rf AppDir linuxdeploy\.AppImage/);
    expect(linux).toMatch(/df -h/);
  });

  it('pins the Debian compressor and leaves evidence when it fails', () => {
    const linux = job('build-linux');
    // The image default (zstd level 19) runs in a helper that has died
    // silently on the runner mid-stream.
    expect(linux).toMatch(/dpkg-deb --build --root-owner-group -Zxz -z6 pkg/);
    expect(linux).toMatch(/TMPDIR=/);
    expect(linux).toMatch(/free -m/);
    expect(linux).toMatch(/dmesg/);
  });

  it('installs per-user on Windows without admin rights', () => {
    const windows = job('build-windows');
    expect(windows).toMatch(/PrivilegesRequired=lowest/);
    expect(windows).not.toMatch(/PrivilegesRequired=admin/);
    expect(windows).toMatch(
      /DefaultDirName=\{localappdata\}\\Programs\\MiniERP/,
    );
    expect(windows).toMatch(/\{userprograms\}/);
    expect(windows).toMatch(/\{userdesktop\}/);
    // Release\* must recurse into the staged server payload.
    expect(windows).toMatch(/Release\\\*/);
    expect(windows).toMatch(/server\\runtime\\node\.exe/);
  });

  it('ships arm64 and Intel macOS images with the server inside the app', () => {
    const macos = job('build-macos');
    expect(macos).toMatch(/runner: macos-15-intel/);
    expect(macos).toMatch(/arch: arm64/);
    expect(macos).toMatch(/arch: x64/);
    expect(macos).toMatch(/Contents\/Resources\/server/);
    expect(macos).toMatch(/codesign --force --deep --sign -/);
    expect(macos).toMatch(/codesign --verify --deep --strict/);
    expect(macos).toMatch(/macos-\$\{\{ matrix\.arch \}\}\.dmg/);
  });

  it('turns off the macOS App Sandbox so the app can spawn the server', () => {
    for (const file of ['Release.entitlements', 'DebugProfile.entitlements']) {
      const plist = fs.readFileSync(
        path.join(REPO_ROOT, 'macos', 'Runner', file),
        'utf8',
      );
      expect(plist).not.toMatch(/com\.apple\.security\.app-sandbox/);
    }
    const pbxproj = fs.readFileSync(
      path.join(REPO_ROOT, 'macos', 'Runner.xcodeproj', 'project.pbxproj'),
      'utf8',
    );
    expect(pbxproj).not.toMatch(/MACOSX_DEPLOYMENT_TARGET = 10\./);
    expect(pbxproj).toMatch(/MACOSX_DEPLOYMENT_TARGET = 11\.0;/);
  });

  it('never seeds or migrates a default admin password', () => {
    const builder = fs.readFileSync(
      path.join(REPO_ROOT, 'tool', 'make_linux_setup.sh'),
      'utf8',
    );
    // The password is passed only through the first boot's environment.
    expect(builder).not.toMatch(/admin123/);
    expect(builder).toMatch(/grep -v '\^DEFAULT_ADMIN_PASSWORD='/);
  });

  it('publishes exactly six self-contained assets and no separate server zip', () => {
    expect(yaml).not.toMatch(/server\.zip/);
    expect(yaml).not.toMatch(/separate-install/);

    const release = job('release');
    expect(release).toMatch(
      /needs: \[build-linux, build-windows, build-macos\]/,
    );
    for (const asset of [
      '-linux-x64.deb',
      '-linux-x64.AppImage',
      '-linux-x64.run',
      '-windows-x64.exe',
      '-macos-arm64.dmg',
      '-macos-x64.dmg',
    ]) {
      expect(release).toContain(asset);
    }
    expect(release).toContain('"$count" -ne 6');
  });
});
