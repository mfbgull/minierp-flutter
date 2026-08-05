"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const dotenv_1 = __importDefault(require("dotenv"));
dotenv_1.default.config();
const app_1 = __importDefault(require("./src/app"));
const database_1 = __importDefault(require("./src/config/database"));
const settingsController_1 = __importDefault(require("./src/controllers/settingsController"));
const logger_1 = __importDefault(require("./src/utils/logger"));
const PORT = parseInt(process.env.PORT || '3011', 10);
const HOST = process.env.BIND_ADDRESS || process.env.HOST || '127.0.0.1';
settingsController_1.default.initializeDefaults();
// Startup validation: check required env vars
const requiredEnvVars = ['JWT_SECRET'];
if (process.env.NODE_ENV === 'production') {
    requiredEnvVars.push('DEFAULT_ADMIN_PASSWORD');
}
const missingEnvVars = requiredEnvVars.filter(v => !process.env[v]);
if (missingEnvVars.length > 0) {
    logger_1.default.error(`Missing required environment variables: ${missingEnvVars.join(', ')}`);
    process.exit(1);
}
const server = app_1.default.listen(PORT, HOST, () => {
    console.log('\n=================================');
    console.log('🚀 Mini ERP Server Started');
    console.log('=================================');
    console.log(`📍 Local:    http://localhost:${PORT}`);
    console.log(`📍 Network:  http://${getLocalIP()}:${PORT}`);
    console.log(`🗄️  Database: SQLite (./database/erp.db)`);
    console.log('=================================\n');
});
function getLocalIP() {
    const { networkInterfaces } = require('os');
    const nets = networkInterfaces();
    for (const name of Object.keys(nets)) {
        for (const net of nets[name]) {
            if (net.family === 'IPv4' && !net.internal) {
                return net.address;
            }
        }
    }
    return '0.0.0.0';
}
process.on('SIGTERM', () => {
    console.log('SIGTERM received. Closing server...');
    server.close(() => {
        console.log('Server closed');
        database_1.default.close();
        process.exit(0);
    });
});
process.on('SIGINT', () => {
    console.log('\nSIGINT received. Closing server...');
    server.close(() => {
        console.log('Server closed');
        database_1.default.close();
        process.exit(0);
    });
});
process.on('unhandledRejection', (reason) => {
    logger_1.default.error('Unhandled Rejection:', reason);
    server.close(() => {
        database_1.default.close();
        process.exit(1);
    });
});
process.on('uncaughtException', (error) => {
    logger_1.default.error('Uncaught Exception:', error);
    server.close(() => {
        database_1.default.close();
        process.exit(1);
    });
});
//# sourceMappingURL=server.js.map