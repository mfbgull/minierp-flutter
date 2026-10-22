'use strict';

class UsageError extends Error {}

function parseGuardOption(argv, index, opts) {
  const flag = argv[index];
  switch (flag) {
    case '--force-incomplete':
      opts.forceIncomplete = true;
      return index;
    case '--reason':
      opts.reason = argv[index + 1];
      if (!opts.reason) throw new UsageError('--reason requires a value');
      return index + 1;
    default:
      if (flag.startsWith('--reason=')) {
        opts.reason = flag.slice('--reason='.length);
        return index;
      }
      throw new UsageError(`unknown flag: ${flag}`);
  }
}

function parseArgv(argv) {
  const change = argv[0];
  if (!change || change.startsWith('--')) {
    throw new UsageError('usage: openspec-archive-guard <change-name> [--force-incomplete --reason "<text>"] [-- <archive flags>]');
  }
  const opts = { change, forceIncomplete: false, reason: null, passthrough: [] };
  let passthrough = false;

  for (let i = 1; i < argv.length; i++) {
    const a = argv[i];
    if (passthrough) { opts.passthrough.push(a); continue; }
    if (a === '--') { passthrough = true; continue; }
    i = parseGuardOption(argv, i, opts);
  }

  if (opts.forceIncomplete && !opts.reason) {
    throw new UsageError('--force-incomplete requires --reason "<text>". An incomplete archive with no recorded reason is exactly the failure this guard exists to prevent.');
  }
  return opts;
}

module.exports = { UsageError, parseGuardOption, parseArgv };
