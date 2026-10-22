import { createRequire } from 'module';

interface GuardOptions {
  change: string;
  forceIncomplete: boolean;
  reason: string | null;
  passthrough: string[];
}

const requireFromHere = createRequire(__filename);
const { parseArgv } = requireFromHere('../../scripts/lib/openspec-archive-guard.js') as {
  parseArgv: (argv: string[]) => GuardOptions;
};

describe('openspec archive guard argument parsing', () => {
  it('parses a bare change name', () => {
    expect(parseArgv(['change-a'])).toEqual({
      change: 'change-a',
      forceIncomplete: false,
      reason: null,
      passthrough: [],
    });
  });

  it('parses --force-incomplete with a separate --reason value', () => {
    expect(parseArgv(['change-a', '--force-incomplete', '--reason', 'done'])).toEqual({
      change: 'change-a',
      forceIncomplete: true,
      reason: 'done',
      passthrough: [],
    });
  });

  it('parses --force-incomplete with --reason=value', () => {
    expect(parseArgv(['change-a', '--force-incomplete', '--reason=done'])).toEqual({
      change: 'change-a',
      forceIncomplete: true,
      reason: 'done',
      passthrough: [],
    });
  });

  it('accepts --reason without --force-incomplete', () => {
    expect(parseArgv(['change-a', '--reason', 'note'])).toEqual({
      change: 'change-a',
      forceIncomplete: false,
      reason: 'note',
      passthrough: [],
    });
  });

  it('rejects --force-incomplete without a reason', () => {
    expect(() => parseArgv(['change-a', '--force-incomplete'])).toThrow(
      /--force-incomplete requires --reason/
    );
  });

  it('rejects --reason without a value', () => {
    expect(() => parseArgv(['change-a', '--reason'])).toThrow(/--reason requires a value/);
  });

  it('rejects an unknown flag', () => {
    expect(() => parseArgv(['change-a', '--bogus'])).toThrow(/unknown flag: --bogus/);
  });

  it('rejects a missing change name or a leading flag', () => {
    expect(() => parseArgv([])).toThrow(/usage: openspec-archive-guard/);
    expect(() => parseArgv(['--force-incomplete'])).toThrow(/usage: openspec-archive-guard/);
  });

  it('passes through everything after --', () => {
    expect(parseArgv(['change-a', '--', '--dry-run', '--json'])).toEqual({
      change: 'change-a',
      forceIncomplete: false,
      reason: null,
      passthrough: ['--dry-run', '--json'],
    });
  });

  it('treats an empty --reason= as missing when --force-incomplete is set', () => {
    expect(() => parseArgv(['change-a', '--force-incomplete', '--reason='])).toThrow(
      /--force-incomplete requires --reason/
    );
  });
});
