import fs from 'fs';
import os from 'os';
import path from 'path';
import { execFileSync } from 'child_process';
import { pathToFileURL } from 'url';

const STAGER = path.resolve(__dirname, '../../../tool/stage-server.mjs');

describe('staged bcrypt native binaries', () => {
  it.each([
    ['linux', 'x64', 'glibc', 'linux-x64/bcrypt.glibc.node'],
    ['linux', 'arm64', 'musl', 'linux-arm64/bcrypt.musl.node'],
    ['darwin', 'arm64', 'glibc', 'darwin-arm64/bcrypt.node'],
    ['win32', 'x64', 'glibc', 'win32-x64/bcrypt.node'],
  ])('keeps only the selected binary for %s %s %s', (platform, arch, libc, expected) => {
    // Given bcrypt's actual package and loader, including all foreign prebuilds.
    const payload = fs.mkdtempSync(path.join(os.tmpdir(), 'minierp-prebuilds-'));
    try {
      fs.writeFileSync(path.join(payload, 'package.json'), '{}');
      for (const name of ['bcrypt', 'node-gyp-build']) {
        fs.cpSync(path.dirname(require.resolve(`${name}/package.json`)),
          path.join(payload, 'node_modules', name), { recursive: true });
      }
      // When the shared staging operation prunes the installed payload.
      execFileSync(process.execPath, ['--input-type=module', '-e', `
        import { pruneBcryptPrebuilds } from ${JSON.stringify(pathToFileURL(STAGER).href)};
        pruneBcryptPrebuilds(process.argv[1]);
      `, payload], {
        env: { ...process.env, npm_config_platform: platform, npm_config_arch: arch, LIBC: libc },
      });
      // Then scanners see only the target binary, with its original bytes.
      const prebuilds = path.join(payload, 'node_modules/bcrypt/prebuilds');
      const binaries = fs.readdirSync(prebuilds, { recursive: true })
        .filter((name) => String(name).endsWith('.node')).map(String);
      expect(binaries).toEqual([expected.split('/').join(path.sep)]);
      expect(fs.readFileSync(path.join(prebuilds, expected))).toEqual(
        fs.readFileSync(path.join(path.dirname(require.resolve('bcrypt/package.json')), 'prebuilds', expected)),
      );
    } finally {
      fs.rmSync(payload, { recursive: true, force: true });
    }
  });
});
