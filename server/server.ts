import dotenv from 'dotenv';
dotenv.config();
import { Server } from 'http';
import app from './src/app';
import db from './src/config/database';
import settingsController from './src/controllers/settingsController';
import logger from './src/utils/logger';

const PORT = parseInt(process.env.PORT || '3011', 10);
const HOST = process.env.BIND_ADDRESS || process.env.HOST || '127.0.0.1';

settingsController.initializeDefaults();

// Startup validation: check required env vars
const requiredEnvVars = ['JWT_SECRET'];
if (process.env.NODE_ENV === 'production') {
  requiredEnvVars.push('DEFAULT_ADMIN_PASSWORD');
}
const missingEnvVars = requiredEnvVars.filter(v => !process.env[v]);
if (missingEnvVars.length > 0) {
  logger.error(`Missing required environment variables: ${missingEnvVars.join(', ')}`);
  process.exit(1);
}

const server: Server = app.listen(PORT, HOST, () => {
  console.log('\n=================================');
  console.log('🚀 Mini ERP Server Started');
  console.log('=================================');
  console.log(`📍 Local:    http://localhost:${PORT}`);
  console.log(`📍 Network:  http://${getLocalIP()}:${PORT}`);
  console.log(`🗄️  Database: SQLite (./database/erp.db)`);
  console.log('=================================\n');
});

function getLocalIP(): string {
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
    db.close();
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  console.log('\nSIGINT received. Closing server...');
  server.close(() => {
    console.log('Server closed');
    db.close();
    process.exit(0);
  });
});

process.on('unhandledRejection', (reason: unknown) => {
  logger.error('Unhandled Rejection:', reason);
  server.close(() => {
    db.close();
    process.exit(1);
  });
});

process.on('uncaughtException', (error: Error) => {
  logger.error('Uncaught Exception:', error);
  server.close(() => {
    db.close();
    process.exit(1);
  });
});
