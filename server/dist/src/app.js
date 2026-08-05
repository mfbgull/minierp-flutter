"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const helmet_1 = __importDefault(require("helmet"));
const cookie_parser_1 = __importDefault(require("cookie-parser"));
const errorHandler_1 = __importDefault(require("./middleware/errorHandler"));
const rateLimiter_1 = require("./middleware/rateLimiter");
const logger_1 = __importDefault(require("./utils/logger"));
const requestLogger_1 = require("./middleware/requestLogger");
const database_1 = __importDefault(require("./config/database"));
// Import routes
const auth_1 = __importDefault(require("./routes/auth"));
const users_1 = __importDefault(require("./routes/users"));
const roles_1 = __importDefault(require("./routes/roles"));
const activityLog_1 = __importDefault(require("./routes/activityLog"));
const inventory_1 = __importDefault(require("./routes/inventory"));
const purchases_1 = __importDefault(require("./routes/purchases"));
const purchaseOrders_1 = __importDefault(require("./routes/purchaseOrders"));
const sales_1 = __importDefault(require("./routes/sales"));
const production_1 = __importDefault(require("./routes/production"));
const bom_1 = __importDefault(require("./routes/bom"));
const settings_1 = __importDefault(require("./routes/settings"));
const invoices_1 = __importDefault(require("./routes/invoices"));
const customers_1 = __importDefault(require("./routes/customers"));
const payments_1 = __importDefault(require("./routes/payments"));
const reports_1 = __importDefault(require("./routes/reports"));
const pos_1 = __importDefault(require("./routes/pos"));
const expenses_1 = __importDefault(require("./routes/expenses"));
const suppliers_1 = __importDefault(require("./routes/suppliers"));
const employees_1 = __importDefault(require("./routes/employees"));
const mobileInvoices_1 = __importDefault(require("./routes/mobileInvoices"));
const integrations_1 = __importDefault(require("./routes/integrations"));
const dashboard_1 = __importDefault(require("./routes/dashboard"));
const forecasts_1 = __importDefault(require("./routes/forecasts"));
const accounting_1 = __importDefault(require("./routes/accounting"));
const customReports_1 = __importDefault(require("./routes/customReports"));
const path_1 = __importDefault(require("path"));
const fs_1 = __importDefault(require("fs"));
// Create Express app
const app = (0, express_1.default)();
// Security middleware
app.use((0, helmet_1.default)({
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
const getAllowedOrigins = () => {
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
    origin: getAllowedOrigins(),
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
    allowedHeaders: ['Content-Type', 'Authorization'],
};
app.use((0, cors_1.default)(corsOptions));
// Cookie parser
app.use((0, cookie_parser_1.default)());
// Body parsing middleware with limits
app.use(express_1.default.json({ limit: '10mb' }));
app.use(express_1.default.urlencoded({ extended: true, limit: '10mb' }));
// Apply rate limiting to all API routes
app.use('/api/', rateLimiter_1.apiLimiter);
// Request logging middleware
app.use(requestLogger_1.requestLogger);
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
function checkDatabaseHealth() {
    const results = [];
    // Check 1: Database connection
    try {
        const row = database_1.default.prepare('SELECT 1 AS alive').get();
        if (row?.alive === 1) {
            results.push({ name: 'database_connectivity', status: 'ok' });
        }
        else {
            results.push({ name: 'database_connectivity', status: 'fail', detail: 'Unexpected result from probe query' });
        }
    }
    catch (error) {
        results.push({ name: 'database_connectivity', status: 'fail', detail: error.message });
    }
    // Check 2: Critical tables exist
    for (const tableName of CRITICAL_TABLES) {
        try {
            const row = database_1.default.prepare(`
        SELECT name FROM sqlite_master
        WHERE type='table' AND name=?
      `).get(tableName);
            if (row) {
                results.push({ name: `table_${tableName}`, status: 'ok' });
            }
            else {
                results.push({ name: `table_${tableName}`, status: 'fail', detail: `Table '${tableName}' does not exist` });
            }
        }
        catch (error) {
            results.push({ name: `table_${tableName}`, status: 'fail', detail: error.message });
        }
    }
    return results;
}
app.get('/health', (req, res) => {
    const checks = checkDatabaseHealth();
    const criticalFailures = checks.filter((c) => c.status === 'fail' && c.name !== 'table_dashboard_layouts');
    // Determine overall status
    let healthStatus = 'ok';
    let httpStatus = 200;
    if (criticalFailures.length > 0) {
        healthStatus = 'down';
        httpStatus = 503;
    }
    else {
        const hasNonCriticalFailure = checks.some((c) => c.status === 'fail');
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
app.use('/api/auth', auth_1.default);
app.use('/api/users', users_1.default);
app.use('/api/roles', roles_1.default);
app.use('/api/activity-logs', activityLog_1.default);
app.use('/api/inventory', inventory_1.default);
app.use('/api/expenses', expenses_1.default);
app.use('/api/boms', bom_1.default);
app.use('/api/settings', settings_1.default);
app.use('/api/invoices', invoices_1.default);
app.use('/api/customers', customers_1.default);
app.use('/api/payments', payments_1.default);
app.use('/api/reports', reports_1.default);
app.use('/api/pos', pos_1.default);
app.use('/api/suppliers', suppliers_1.default);
app.use('/api/employees', employees_1.default);
app.use('/api', purchaseOrders_1.default);
app.use('/api', purchases_1.default);
app.use('/api', sales_1.default);
app.use('/api', production_1.default);
app.use('/api/mobile-invoices', mobileInvoices_1.default);
app.use('/api/integrations', integrations_1.default);
app.use('/api/dashboard', dashboard_1.default);
app.use('/api/forecasts', forecasts_1.default);
app.use('/api/accounting', accounting_1.default);
app.use('/api/reports/custom', customReports_1.default);
// Serve static files from client/dist in production
// This MUST come AFTER API routes
if (process.env.NODE_ENV === 'production') {
    let clientDistPath;
    // Check if running in Electron (DATABASE_PATH is set by Electron main process)
    if (process.env.DATABASE_PATH) {
        // Running in packaged Electron app
        clientDistPath = path_1.default.join(process.cwd(), '..', 'client', 'dist');
        clientDistPath = path_1.default.normalize(clientDistPath);
        if (!fs_1.default.existsSync(clientDistPath)) {
            logger_1.default.warn('[Server] Path not found, trying alternative locations...');
            clientDistPath = path_1.default.join(__dirname, '..', '..', '..', 'client', 'dist');
            clientDistPath = path_1.default.normalize(clientDistPath);
        }
        if (!fs_1.default.existsSync(clientDistPath)) {
            const resourcesPath = path_1.default.join(path_1.default.dirname(process.execPath), 'resources');
            clientDistPath = path_1.default.join(resourcesPath, 'client', 'dist');
            clientDistPath = path_1.default.normalize(clientDistPath);
        }
    }
    else {
        clientDistPath = path_1.default.join(__dirname, '..', '..', 'client', 'dist');
    }
    logger_1.default.info('[Server] Serving static files from:', { path: clientDistPath });
    logger_1.default.info('[Server] Path exists:', { exists: fs_1.default.existsSync(clientDistPath) });
    logger_1.default.info('[Server] process.cwd():', { cwd: process.cwd() });
    // Serve static assets (js, css, images, etc.)
    app.use(express_1.default.static(clientDistPath, {
        maxAge: '1y',
        setHeaders: (res, filePath) => {
            if (!filePath.endsWith('.html')) {
                res.setHeader('Cache-Control', 'public, max-age=31536000');
            }
        }
    }));
    // SPA catch-all - serve index.html for all non-API routes
    // This enables client-side routing (React Router)
    app.use((req, res, next) => {
        // Skip API routes and health endpoint
        if (req.path.startsWith('/api/') || req.path === '/health') {
            return next();
        }
        const indexPath = path_1.default.join(clientDistPath, 'index.html');
        if (fs_1.default.existsSync(indexPath)) {
            res.sendFile(indexPath);
        }
        else {
            logger_1.default.error('[Server] index.html not found at:', { path: indexPath });
            res.status(404).json({ error: 'Route not found', path: req.path });
        }
    });
}
else {
    // In development, serve the built frontend for SPA routing
    const clientDistPath = path_1.default.join(__dirname, '..', '..', 'client', 'dist');
    const normalizedPath = path_1.default.normalize(clientDistPath);
    logger_1.default.info('[Server] Serving static files from:', { path: normalizedPath });
    // Serve static assets
    app.use(express_1.default.static(normalizedPath));
    // SPA catch-all - serve index.html for all non-API routes
    // This enables client-side routing (React Router)
    app.use((req, res, next) => {
        // Skip API routes and health endpoint
        if (req.path.startsWith('/api/') || req.path === '/health') {
            return next();
        }
        const indexPath = path_1.default.join(normalizedPath, 'index.html');
        if (fs_1.default.existsSync(indexPath)) {
            res.sendFile(indexPath);
        }
        else {
            logger_1.default.error('[Server] index.html not found at:', { path: indexPath });
            res.status(404).json({ error: 'Route not found', path: req.path });
        }
    });
}
// Error logging middleware (before error handler)
app.use(requestLogger_1.errorLogger);
// Global error handler
app.use(errorHandler_1.default.errorHandler);
exports.default = app;
//# sourceMappingURL=app.js.map