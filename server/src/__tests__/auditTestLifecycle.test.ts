import { afterAll, expect, test } from '@jest/globals';
import db from '../config/database';
import { ActionType, logCRUD } from '../services/activityLogger';

const marker = 'Lifecycle fixture audit must persist before cleanup';

test('queues a valid audit event at the end of a fixture', () => {
  const user = db.prepare<[], { id: number }>('SELECT id FROM users ORDER BY id LIMIT 1').get();
  if (!user) throw new Error('Missing seeded fixture user');
  const customer = db.prepare(`INSERT INTO customers (customer_code,customer_name)
    VALUES ('AUDIT-LIFECYCLE','Lifecycle fixture')`).run();
  logCRUD(ActionType.CUSTOMER_CREATE, 'Customer', Number(customer.lastInsertRowid), marker, user.id);
  expect(db.prepare<[string], { count: number }>(
    'SELECT COUNT(*) count FROM activity_log WHERE description=?',
  ).get(marker)?.count).toBe(0);
});

// The shared setup's afterAll runs first. Its cleanup must finish pending audit
// work before removing the fixture files and closing the logging transports.
afterAll(() => {
  const row = db.prepare<[string], { count: number }>(
    'SELECT COUNT(*) count FROM activity_log WHERE description=?',
  ).get(marker);
  expect(row?.count).toBe(1);
});
