import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import db from '../config/database';
import activityLogModel from '../models/ActivityLog';
import logger from '../utils/logger';

/**
 * Fallow health remediation — `ActivityLogModel.insert` (CRAP 42) and the
 * CSV `rows` mapper (CRAP 30).
 */
describe('ActivityLogModel', () => {
  let adminId = 0;

  beforeAll(() => {
    adminId = (
      db.prepare(`SELECT id FROM users WHERE username = 'admin'`).get() as { id: number }
    ).id;
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('insert', () => {
    it('writes every optional column', () => {
      const id = activityLogModel.insert(
        adminId,
        'ITEM_UPDATE',
        'Item',
        5,
        'Updated item',
        'WARN',
        '10.0.0.1',
        'jest-agent',
        { field: 'quantity' },
        12
      );

      const row = db.prepare('SELECT * FROM activity_log WHERE id = ?').get(id) as Record<
        string,
        unknown
      >;
      expect(row).toMatchObject({
        user_id: adminId,
        action: 'ITEM_UPDATE',
        entity_type: 'Item',
        entity_id: 5,
        description: 'Updated item',
        log_level: 'WARN',
        ip_address: '10.0.0.1',
        user_agent: 'jest-agent',
        metadata: JSON.stringify({ field: 'quantity' }),
        duration_ms: 12,
      });
    });

    it('defaults null user/entity and leaves optional columns null', () => {
      const id = activityLogModel.insert(null, 'SYSTEM', 'Setting', null, 'Ran cleanup');

      const row = db.prepare('SELECT * FROM activity_log WHERE id = ?').get(id) as Record<
        string,
        unknown
      >;
      expect(row).toMatchObject({
        user_id: null,
        entity_id: null,
        log_level: 'INFO',
        ip_address: null,
        user_agent: null,
        metadata: null,
        duration_ms: null,
      });
    });

    it('treats empty optional strings and a zero duration as absent', () => {
      const id = activityLogModel.insert(
        null,
        'SYSTEM',
        'Setting',
        1,
        'Ran cleanup',
        'INFO',
        '',
        '',
        undefined,
        0
      );

      const row = db.prepare('SELECT * FROM activity_log WHERE id = ?').get(id) as Record<
        string,
        unknown
      >;
      expect(row).toMatchObject({
        ip_address: null,
        user_agent: null,
        metadata: null,
        duration_ms: null,
      });
    });

    it('returns 0 instead of throwing when the insert fails', () => {
      jest.spyOn(logger, 'error').mockImplementation(() => logger);
      jest.spyOn(db, 'prepare').mockImplementation(() => {
        throw new Error('forced insert failure');
      });

      expect(
        activityLogModel.insert(null, 'SYSTEM', 'Setting', null, 'will fail')
      ).toBe(0);
      expect(logger.error).toHaveBeenCalledWith(
        '[ActivityLogModel] Insert failed:',
        'forced insert failure'
      );
    });
  });

  describe('exportToCSV', () => {
    it('renders headers, escaping quotes and defaulting missing values', () => {
      activityLogModel.insert(
        adminId,
        'EXPORT_ONE',
        'Item',
        3,
        'Said "hello"',
        'INFO',
        '192.168.1.9'
      );
      activityLogModel.insert(null, 'EXPORT_TWO', 'Setting', null, 'system row');

      const itemCsv = activityLogModel.exportToCSV({ entityType: 'Item' });
      const settingCsv = activityLogModel.exportToCSV({ entityType: 'Setting' });

      expect(itemCsv.split('\n')[0]).toBe(
        'ID,User,Action,Entity Type,Entity ID,Description,Level,IP Address,Created At'
      );
      expect(itemCsv).toContain(`"Said ""hello"""`);
      expect(itemCsv).toContain(',admin,EXPORT_ONE,Item,3,');
      expect(itemCsv).toContain('192.168.1.9');
      expect(settingCsv).toContain(',System,EXPORT_TWO,Setting,,"system row",');
    });
  });
});
