"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.authenticateToken = authenticateToken;
exports.requireAdmin = requireAdmin;
exports.generateToken = generateToken;
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
const logger_1 = __importDefault(require("../utils/logger"));
if (!process.env.JWT_SECRET) {
    throw new Error('FATAL: JWT_SECRET environment variable must be set. Generate one with: openssl rand -base64 64');
}
const JWT_SECRET = process.env.JWT_SECRET;
function authenticateToken(req, res, next) {
    const authHeader = req.headers['authorization'];
    const token = req.cookies?.token || (authHeader?.startsWith('Bearer ')
        ? authHeader.slice(7)
        : null);
    if (!token) {
        res.status(401).json({ error: 'Access token required' });
        return;
    }
    try {
        const user = jsonwebtoken_1.default.verify(token, JWT_SECRET, {
            algorithms: ['HS256'],
            issuer: 'mini-erp',
            audience: 'mini-erp-client'
        });
        req.user = user;
        next();
    }
    catch (err) {
        logger_1.default.warn(`[Auth] Token verification failed: ${err.name} from IP ${req.ip}`);
        // In production, return generic error to prevent information leakage
        if (process.env.NODE_ENV === 'production') {
            res.status(401).json({ error: 'Unauthorized', code: 'AUTH_FAILED' });
            return;
        }
        if (err.name === 'TokenExpiredError') {
            res.status(401).json({ error: 'Token expired', code: 'TOKEN_EXPIRED' });
        }
        else if (err.name === 'JsonWebTokenError') {
            res.status(403).json({ error: 'Invalid token', code: 'INVALID_TOKEN' });
        }
        else {
            res.status(403).json({ error: 'Token verification failed', code: 'AUTH_FAILED' });
        }
    }
}
function requireAdmin(req, res, next) {
    if (!req.user) {
        res.status(401).json({ error: 'Authentication required' });
        return;
    }
    if (req.user.role !== 'admin') {
        logger_1.default.warn(`[Auth] Admin access denied for user ${req.user.username} (${req.user.id})`);
        res.status(403).json({ error: 'Admin access required' });
        return;
    }
    next();
}
function generateToken(user) {
    return jsonwebtoken_1.default.sign({ id: user.id, username: user.username, email: user.email, role: user.role }, JWT_SECRET, { expiresIn: '24h', issuer: 'mini-erp', audience: 'mini-erp-client', algorithm: 'HS256' });
}
exports.default = { authenticateToken, requireAdmin, generateToken };
//# sourceMappingURL=auth.js.map