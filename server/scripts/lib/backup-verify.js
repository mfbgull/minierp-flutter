'use strict';

const fs = require('fs');
const Database = require('better-sqlite3');

/**
 * Runs integrity_check on a snapshot file. Deletes the snapshot on a
 * non-'ok' result, matching the backup CLI's failure behavior.
 */
function verifySnapshotAt(snapshotPath) {
  let checkDb;
  try {
    checkDb = new Database(snapshotPath, { readonly: true });
    const row = checkDb.pragma('integrity_check', { simple: true });
    if (row !== 'ok') {
      fs.rmSync(snapshotPath, { force: true });
      return { ok: false, message: `integrity_check failed on snapshot: ${row}` };
    }
    return { ok: true };
  } catch (err) {
    return {
      ok: false,
      message: `integrity_check could not run: ${err && err.message ? err.message : err}`,
    };
  } finally {
    if (checkDb) {
      try {
        checkDb.close();
      } catch {
        /* best effort */
      }
    }
  }
}

module.exports = { verifySnapshotAt };
