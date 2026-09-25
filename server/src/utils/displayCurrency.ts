import type Database from 'better-sqlite3';

import Settings from '../models/Settings';

const DEFAULT_CURRENCY_SYMBOL = 'Rs.';
const amountFormatter = new Intl.NumberFormat('en-US', {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

export function getCurrencySymbol(db: Database.Database): string {
  return Settings.getByKey(db, 'currency_symbol')?.value.trim() ||
    DEFAULT_CURRENCY_SYMBOL;
}

export function formatCurrency(value: number, symbol: string): string {
  const normalizedSymbol = symbol.trim() || DEFAULT_CURRENCY_SYMBOL;
  return `${normalizedSymbol} ${amountFormatter.format(value)}`;
}
