
require('ts-node').register({ transpileOnly: true, project: '/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/tsconfig.json' });
try { require('/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/config/database.ts'); console.log('BOOT OK'); }
catch (e) { console.log('caught:', e.message); }
