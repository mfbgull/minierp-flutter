const fs = require('node:fs');
const readline = require('node:readline');

async function report(paths) {
  const routes = {};
  for (const path of paths) {
    const lines = readline.createInterface({ input: fs.createReadStream(path), crlfDelay: Infinity });
    for await (const line of lines) {
      let event;
      try { event = JSON.parse(line); } catch { continue; }
      if (event.event !== 'invoice_idempotency_observation' || typeof event.route !== 'string' || typeof event.keyed !== 'boolean') continue;
      const counts = routes[event.route] ??= { keyed: 0, keyless: 0 };
      counts[event.keyed ? 'keyed' : 'keyless'] += 1;
    }
  }
  return routes;
}

if (require.main === module) {
  if (process.argv.length < 3) {
    console.error('Usage: node scripts/invoice-idempotency-report.cjs logs/combined.log [archived-log ...]');
    process.exitCode = 1;
  } else {
    report(process.argv.slice(2)).then(result => console.log(JSON.stringify(result, null, 2))).catch(error => {
      console.error(error.message);
      process.exitCode = 1;
    });
  }
}

module.exports = { report };
