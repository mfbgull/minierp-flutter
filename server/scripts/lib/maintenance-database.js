const path = require('path');
const fs = require('fs');

function openMaintenanceDatabase(scriptDirectory, scriptName) {
  const candidates = [
    process.env.DATABASE_PATH && path.join(process.env.DATABASE_PATH, 'erp.db'),
    process.env.DATABASE_PATH,
    path.join(scriptDirectory, '../../../database/erp.db'),
    path.join(scriptDirectory, '../../database/erp.db'),
  ].filter(Boolean);
  const dbPath = candidates.find(candidate => fs.existsSync(candidate));
  if (!dbPath) {
    console.error(`[${scriptName}] database not found; set DATABASE_PATH`);
    process.exit(1);
  }
  const Database = require('better-sqlite3');
  return new Database(dbPath);
}

module.exports = { openMaintenanceDatabase };
