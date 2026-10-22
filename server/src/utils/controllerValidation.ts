import type { Response } from 'express';

export function positiveFiniteAmount(value: unknown): number | null {
  const amount = Number(value);
  return Number.isFinite(amount) && amount > 0 ? amount : null;
}

export function requireReportDateRange(startDate: unknown, endDate: unknown, res: Response): boolean {
  if (startDate && endDate) return true;
  res.status(400).json({ success: false, error: 'startDate and endDate are required' });
  return false;
}
