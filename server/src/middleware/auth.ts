import jwt from 'jsonwebtoken';
import { Response, NextFunction } from 'express';
import { AuthUser, AuthRequest } from '../types';
import logger from '../utils/logger';

if (!process.env.JWT_SECRET) {
  throw new Error('FATAL: JWT_SECRET environment variable must be set. Generate one with: openssl rand -base64 64');
}

const JWT_SECRET = process.env.JWT_SECRET!;

export function authenticateToken(
  req: AuthRequest,
  res: Response,
  next: NextFunction
): void {
  const authHeader = req.headers['authorization'];
  const token = req.cookies?.token || (authHeader?.startsWith('Bearer ')
    ? authHeader.slice(7)
    : null);

  if (!token) {
    res.status(401).json({ error: 'Access token required' });
    return;
  }

  try {
    const user = jwt.verify(token, JWT_SECRET, {
      algorithms: ['HS256'],
      issuer: 'mini-erp',
      audience: 'mini-erp-client'
    }) as AuthUser;

    req.user = user;
    next();
  } catch (err: any) {
    logger.warn(`[Auth] Token verification failed: ${err.name} from IP ${req.ip}`);
    
    // In production, return generic error to prevent information leakage
    if (process.env.NODE_ENV === 'production') {
      res.status(401).json({ error: 'Unauthorized', code: 'AUTH_FAILED' });
      return;
    }

    if (err.name === 'TokenExpiredError') {
      res.status(401).json({ error: 'Token expired', code: 'TOKEN_EXPIRED' });
    } else if (err.name === 'JsonWebTokenError') {
      res.status(403).json({ error: 'Invalid token', code: 'INVALID_TOKEN' });
    } else {
      res.status(403).json({ error: 'Token verification failed', code: 'AUTH_FAILED' });
    }
  }
}

export function requireAdmin(
  req: AuthRequest,
  res: Response,
  next: NextFunction
): void {
  if (!req.user) {
    res.status(401).json({ error: 'Authentication required' });
    return;
  }

  if (req.user.role !== 'admin') {
    logger.warn(`[Auth] Admin access denied for user ${req.user.username} (${req.user.id})`);
    res.status(403).json({ error: 'Admin access required' });
    return;
  }
  next();
}

export function generateToken(user: AuthUser): string {
  // HS256 is explicitly pinned with issuer/audience below — mimosa-ignore
  return jwt.sign(
    { id: user.id, username: user.username, email: user.email, role: user.role },
    JWT_SECRET,
    { expiresIn: '1h', issuer: 'mini-erp', audience: 'mini-erp-client', algorithm: 'HS256' }
  );
}

/// Long-lived token exchanged for a fresh access token by `POST
/// /auth/refresh`. Carries a `type: 'refresh'` claim so access tokens can
/// never be used as refresh tokens.
export function generateRefreshToken(user: AuthUser): string {
  return jwt.sign(
    {
      id: user.id,
      username: user.username,
      email: user.email,
      role: user.role,
      type: 'refresh',
    },
    JWT_SECRET,
    { expiresIn: '7d', issuer: 'mini-erp', audience: 'mini-erp-client', algorithm: 'HS256' }
  );
}

/// Verifies a refresh token. Returns the embedded user, or `null` for
/// missing/expired/wrong-type tokens.
export function verifyRefreshToken(token: string): AuthUser | null {
  try {
    const payload = jwt.verify(token, JWT_SECRET, {
      algorithms: ['HS256'],
      issuer: 'mini-erp',
      audience: 'mini-erp-client',
    }) as AuthUser & { type?: string };
    return payload.type === 'refresh' ? payload : null;
  } catch {
    return null;
  }
}

export default { authenticateToken, requireAdmin, generateToken, generateRefreshToken, verifyRefreshToken };
