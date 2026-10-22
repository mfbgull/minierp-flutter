export function localMonthCode(date: Date, order: 'MMYY' | 'YYMM' = 'MMYY'): string {
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const year = String(date.getFullYear()).slice(-2);
  return order === 'MMYY' ? `${month}${year}` : `${year}${month}`;
}
