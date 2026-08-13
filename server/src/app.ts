import express, { Express } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import cookieParser from 'cookie-parser';
import errorHandlerMiddleware from './middleware/errorHandler';
import { apiLimiter } from './middleware/rateLimiter';
import logger from './utils/logger';
import { requestLogger, errorLogger } from './middleware/requestLogger';
import db from './config/database';

// Import routes
import authRoutes from './routes/auth';
import userRoutes from './routes/users';
import roleRoutes from './routes/roles';
import activityLogRoutes from './routes/activityLog';
import inventoryRoutes from './routes/inventory';
import purchaseRoutes from './routes/purchases';
import purchaseOrderRoutes from './routes/purchaseOrders';
import saleRoutes from './routes/sales';
import productionRoutes from './routes/production';
import bomRoutes from './routes/bom';
import settingsRoutes from './routes/settings';
import invoiceRoutes from './routes/invoices';
import customerRoutes from './routes/customers';
import paymentRoutes from './routes/payments';
import reportRoutes from './routes/reports';
import posRoutes from './routes/pos';
import expenseRoutes from './routes/expenses';
import supplierRoutes from './routes/suppliers';
import employeeRoutes from './routes/employees';
import mobileInvoiceRoutes from './routes/mobileInvoices';
import integrationRoutes from './routes/integrations';
import dashboardRoutes from './routes/dashboard';
import forecastsRoutes from './routes/forecasts';
import accountingRoutes from './routes/accounting';
import customReportsRoutes from './routes/customReports';
import preferencesRoutes from './routes/preferences';
import path from 'path';
import fs from 'fs';

// Create Express app
const app: Express = express();

// Security middleware
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      scriptSrc: ["'self'"],
      imgSrc: ["'self'", "data:", "blob:"],
      connectSrc: ["'self'"],
      fontSrc: ["'self'"],
      objectSrc: ["'none'"],
      frameAncestors: ["'none'"],
      baseUri: ["'self'"],
      formAction: ["'self'"],
    },
  },
  crossOriginEmbedderPolicy: false,
  referrerPolicy: { policy: 'strict-origin-when-cross-origin' },
}));

// CORS configuration
const getAllowedOrigins = (): string | string[] => {
  if (process.env.NODE_ENV === 'production') {
    const origins = process.env.ALLOWED_ORIGINS;
    if (!origins) {
      throw new Error('FATAL: ALLOWED_ORIGINS must be set in production. Set it in your environment variables.');
    }
    return origins.split(',').map(o => o.trim());
  }
  return ['http://localhost:3010', 'http://localhost:3011', 'http://127.0.0.1:3010', 'http://127.0.0.1:3011'];
};

const corsOptions = {
  // In development allow any origin (the Flutter web dev server runs on a
  // random port, so a fixed whitelist would block it). Production still
  // enforces ALLOWED_ORIGINS via index.ts's eager getter.
  origin: function (
    origin: string | undefined,
    callback: (err: Error | null, allow?: boolean) => void
  ) {
    if (process.env.NODE_ENV !== 'production') {
      callback(null, true);
      return;
    }
    const allowed = getAllowedOrigins();
    const list = Array.isArray(allowed) ? allowed : [allowed];
    callback(null, !origin || list.includes(origin));
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
  allowedHeaders: ['Content-Type', 'Authorization'],
};

app.use(cors(corsOptions));

// Cookie parser
app.use(cookieParser());

// Body parsing middleware with limits
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Apply rate limiting to all API routes
app.use('/api/', apiLimiter);

// Request logging middleware
app.use(requestLogger);

/**
 * Health check endpoint — verifies server liveness AND readiness.
 *
 * Returns HTTP 200 when all critical subsystems are healthy.
 * Returns HTTP 503 when any critical check fails (database, core tables).
 *
 * Response:
 * {
 *   status: 'ok' | 'degraded' | 'down',
 *   timestamp: ISO string,
 *   uptime: seconds,
 *   checks: { name: string, status: 'ok' | 'fail', detail?: string }[]
 * }
 */

/** Critical tables that must exist for the app to function */
const CRITICAL_TABLES = [
  'users',
  'items',
  'invoices',
  'dashboard_layouts',
  'roles',
  'permissions',
];

function checkDatabaseHealth(): Array<{ name: string; status: 'ok' | 'fail'; detail?: string }> {
  const results: Array<{ name: string; status: 'ok' | 'fail'; detail?: string }> = [];

  // Check 1: Database connection
  try {
    const row = db.prepare('SELECT 1 AS alive').get() as { alive: number };
    if (row?.alive === 1) {
      results.push({ name: 'database_connectivity', status: 'ok' });
    } else {
      results.push({ name: 'database_connectivity', status: 'fail', detail: 'Unexpected result from probe query' });
    }
  } catch (error: any) {
    results.push({ name: 'database_connectivity', status: 'fail', detail: error.message });
  }

  // Check 2: Critical tables exist
  for (const tableName of CRITICAL_TABLES) {
    try {
      const row = db.prepare(`
        SELECT name FROM sqlite_master
        WHERE type='table' AND name=?
      `).get(tableName) as { name: string } | undefined;

      if (row) {
        results.push({ name: `table_${tableName}`, status: 'ok' });
      } else {
        results.push({ name: `table_${tableName}`, status: 'fail', detail: `Table '${tableName}' does not exist` });
      }
    } catch (error: any) {
      results.push({ name: `table_${tableName}`, status: 'fail', detail: error.message });
    }
  }

  return results;
}

app.get('/health', (req: express.Request, res: express.Response) => {
  const checks = checkDatabaseHealth();

  const criticalFailures = checks.filter(
    (c) => c.status === 'fail' && c.name !== 'table_dashboard_layouts', // dashboard_layouts is optional until first save
  );

  // Determine overall status
  let healthStatus: 'ok' | 'degraded' | 'down' = 'ok';
  let httpStatus = 200;

  if (criticalFailures.length > 0) {
    healthStatus = 'down';
    httpStatus = 503;
  } else {
    const hasNonCriticalFailure = checks.some(
      (c) => c.status === 'fail',
    );
    if (hasNonCriticalFailure) {
      healthStatus = 'degraded';
    }
  }

  res.status(httpStatus).json({
    status: healthStatus,
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    environment: process.env.NODE_ENV || 'development',
    checks,
  });
});

// API Routes - MUST come before SPA catch-all
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/roles', roleRoutes);
app.use('/api/activity-logs', activityLogRoutes);
app.use('/api/inventory', inventoryRoutes);
app.use('/api/expenses', expenseRoutes);
app.use('/api/boms', bomRoutes);
app.use('/api/settings', settingsRoutes);
app.use('/api/invoices', invoiceRoutes);
app.use('/api/customers', customerRoutes);
app.use('/api/payments', paymentRoutes);
app.use('/api/reports', reportRoutes);
app.use('/api/pos', posRoutes);
app.use('/api/suppliers', supplierRoutes);
app.use('/api/employees', employeeRoutes);
app.use('/api', purchaseOrderRoutes);
app.use('/api', purchaseRoutes);
app.use('/api', saleRoutes);
app.use('/api', productionRoutes);
app.use('/api/mobile-invoices', mobileInvoiceRoutes);
app.use('/api/integrations', integrationRoutes);
app.use('/api/dashboard', dashboardRoutes);
app.use('/api/forecasts', forecastsRoutes);
app.use('/api/accounting', accountingRoutes);
app.use('/api/reports/custom', customReportsRoutes);
app.use('/api/preferences', preferencesRoutes);

// Serve static files from client/dist in production
// This MUST come AFTER API routes
if (process.env.NODE_ENV === 'production') {
  let clientDistPath: string;

  // Check if running in Electron (DATABASE_PATH is set by Electron main process)
  if (process.env.DATABASE_PATH) {
    // Running in packaged Electron app
    clientDistPath = path.join(process.cwd(), '..', 'client', 'dist');
    clientDistPath = path.normalize(clientDistPath);

    if (!fs.existsSync(clientDistPath)) {
      logger.warn('[Server] Path not found, trying alternative locations...');

      clientDistPath = path.join(__dirname, '..', '..', '..', 'client', 'dist');
      clientDistPath = path.normalize(clientDistPath);
    }

    if (!fs.existsSync(clientDistPath)) {
      const resourcesPath = path.join(path.dirname(process.execPath), 'resources');
      clientDistPath = path.join(resourcesPath, 'client', 'dist');
      clientDistPath = path.normalize(clientDistPath);
    }
  } else {
    clientDistPath = path.join(__dirname, '..', '..', 'client', 'dist');
  }

  logger.info('[Server] Serving static files from:', { path: clientDistPath });
  logger.info('[Server] Path exists:', { exists: fs.existsSync(clientDistPath) });
  logger.info('[Server] process.cwd():', { cwd: process.cwd() });

  // Serve static assets (js, css, images, etc.)
  app.use(express.static(clientDistPath, {
    maxAge: '1y',
    setHeaders: (res: any, filePath: string) => {
      if (!filePath.endsWith('.html')) {
        res.setHeader('Cache-Control', 'public, max-age=31536000');
      }
    }
  }));

  // SPA catch-all - serve index.html for all non-API routes
  // This enables client-side routing (React Router)
  app.use((req: express.Request, res: express.Response, next: express.NextFunction) => {
    // Skip API routes and health endpoint
    if (req.path.startsWith('/api/') || req.path === '/health') {
      return next();
    }
    const indexPath = path.join(clientDistPath, 'index.html');
    if (fs.existsSync(indexPath)) {
      res.sendFile(indexPath);
    } else {
      logger.error('[Server] index.html not found at:', { path: indexPath });
      res.status(404).json({ error: 'Route not found', path: req.path });
    }
  });
} else {
  // In development, serve the built frontend for SPA routing
  const clientDistPath = path.join(__dirname, '..', '..', 'client', 'dist');
  const normalizedPath = path.normalize(clientDistPath);

  logger.info('[Server] Serving static files from:', { path: normalizedPath });

  // Serve static assets
  app.use(express.static(normalizedPath));

  // SPA catch-all - serve index.html for all non-API routes
  // This enables client-side routing (React Router)
  app.use((req: express.Request, res: express.Response, next: express.NextFunction) => {
    // Skip API routes and health endpoint
    if (req.path.startsWith('/api/') || req.path === '/health') {
      return next();
    }
    const indexPath = path.join(normalizedPath, 'index.html');
    if (fs.existsSync(indexPath)) {
      res.sendFile(indexPath);
    } else {
      logger.error('[Server] index.html not found at:', { path: indexPath });
      res.status(404).json({ error: 'Route not found', path: req.path });
    }
  });
}

// Error logging middleware (before error handler)
app.use(errorLogger);

// Global error handler
app.use(errorHandlerMiddleware.errorHandler);

export default app;
