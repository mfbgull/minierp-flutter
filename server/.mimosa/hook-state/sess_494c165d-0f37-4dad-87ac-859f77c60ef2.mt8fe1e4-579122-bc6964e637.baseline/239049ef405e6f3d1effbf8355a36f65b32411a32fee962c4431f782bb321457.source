import bcrypt from 'bcrypt';
import { Request, Response } from 'express';
import { generateToken } from '../middleware/auth';
import { AuthRequest } from '../types';
import { logAuth, ActionType } from '../services/activityLogger';
import db from '../config/database';
import UserModel from '../models/User';
import logger from '../utils/logger';
import { sendSuccess, sendBadRequest, sendUnauthorized, sendNotFound, sendInternalError } from '../utils/apiResponse';

function login(req: Request, res: Response): void {
  try {
    const { username, password } = req.body;
    const ipAddress = req.ip || req.get('x-forwarded-for') || req.get('x-real-ip');
    if (!username || !password) { sendBadRequest(res, 'Username and password required'); return; }

    const user = UserModel.findByUsername(username, db);
    if (!user) {
      logAuth(ActionType.LOGIN_FAILED, undefined, `Failed login attempt for user: ${username}`, { username }, ipAddress);
      req.activityLogged = true;
      sendUnauthorized(res, 'Invalid username or password');
      return;
    }

    const passwordMatch = bcrypt.compareSync(password, user.password_hash!);
    if (!passwordMatch) {
      logAuth(ActionType.LOGIN_FAILED, user.id, `Failed login attempt for user: ${username}`, { username }, ipAddress);
      req.activityLogged = true;
      sendUnauthorized(res, 'Invalid username or password');
      return;
    }

    const token = generateToken({ id: user.id, username: user.username, email: user.email, role: user.role });
    logAuth(ActionType.LOGIN, user.id, `User ${username} logged in successfully`, { username, email: user.email }, ipAddress);
    req.activityLogged = true;

    const { password_hash: _password_hash, ...userWithoutPassword } = user;
    res.cookie('token', token, { httpOnly: true, secure: process.env.NODE_ENV === 'production', sameSite: 'strict', maxAge: 24 * 60 * 60 * 1000 });
    // PORTING.md §0: desktop Flutter has no cookie jar — also return the
    // JWT in the body so the native client can store it as a Bearer token.
    sendSuccess(res, { token, user: userWithoutPassword });
  } catch (error) {
    logger.error('Login error:', error);
    sendInternalError(res, 'Login failed');
  }
}

function logout(req: AuthRequest, res: Response): void {
  try {
    logAuth(ActionType.LOGOUT, req.user?.id, `User ${req.user?.username} logged out`);
    req.activityLogged = true;
    res.clearCookie('token');
    sendSuccess(res, { message: 'Logged out successfully' });
  } catch (error) {
    logger.error('Logout error:', error);
    sendInternalError(res, 'Logout failed');
  }
}

function getCurrentUser(req: AuthRequest, res: Response): void {
  try {
    const user = UserModel.getById(req.user!.id, db);
    if (!user) { sendNotFound(res, 'User'); return; }
    sendSuccess(res, user);
  } catch (error) {
    logger.error('Get current user error:', error);
    sendInternalError(res, 'Failed to get user info');
  }
}

function changePassword(req: AuthRequest, res: Response): void {
  try {
    const { currentPassword, newPassword } = req.body;
    if (!currentPassword || !newPassword) { sendBadRequest(res, 'Current and new password required'); return; }
    if (newPassword.length < 6) { sendBadRequest(res, 'New password must be at least 6 characters'); return; }

    const user = UserModel.getPasswordHash(req.user!.id, db);
    if (!user) { sendNotFound(res, 'User'); return; }

    const passwordMatch = bcrypt.compareSync(currentPassword, user.password_hash);
    if (!passwordMatch) { sendUnauthorized(res, 'Current password is incorrect'); return; }

    UserModel.updatePassword(req.user!.id, bcrypt.hashSync(newPassword, 12), db);
    logAuth(ActionType.PASSWORD_CHANGE, req.user!.id, 'Password changed successfully');
    req.activityLogged = true;
    sendSuccess(res, { message: 'Password changed successfully' });
  } catch (error) {
    logger.error('Change password error:', error);
    sendInternalError(res, 'Failed to change password');
  }
}

export default { login, logout, getCurrentUser, changePassword };
