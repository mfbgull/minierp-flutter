import { weekBounds } from '../utils/weekMath';

describe('weekMath', () => {
  it('returns the monday-first week for a mid-week date', () => {
    expect(weekBounds('2026-08-13')).toEqual({ from: '2026-08-10', to: '2026-08-16' });
  });

  it('returns the saturday-first week', () => {
    expect(weekBounds('2026-08-13', 'saturday')).toEqual({ from: '2026-08-08', to: '2026-08-14' });
  });

  it('returns the sunday-first week', () => {
    expect(weekBounds('2026-08-13', 'sunday')).toEqual({ from: '2026-08-09', to: '2026-08-15' });
  });

  it('is a no-op when the date is itself the week start', () => {
    expect(weekBounds('2026-08-10', 'monday')).toEqual({ from: '2026-08-10', to: '2026-08-16' });
  });

  it('crosses a month boundary', () => {
    // 2026-08-02 is a Sunday.
    expect(weekBounds('2026-08-02', 'monday')).toEqual({ from: '2026-07-27', to: '2026-08-02' });
  });

  it('crosses a year boundary', () => {
    // 2027-01-01 is a Friday.
    expect(weekBounds('2027-01-01', 'monday')).toEqual({ from: '2026-12-28', to: '2027-01-03' });
  });
});
