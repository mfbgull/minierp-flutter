import type { Response } from 'express';

export function respondToClosedPeriod(res: Response, message: string): boolean {
  if (!message.includes('inside closed accounting period')) return false;
  res.status(409).json({ error: message });
  return true;
}
