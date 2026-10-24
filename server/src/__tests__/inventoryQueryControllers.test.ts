import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import PhysicalCountModel from '../models/PhysicalCount';
import { StockReservationModel } from '../models/StockReservation';
import StockMovementModel from '../models/StockMovement';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `inventoryController.getStockBalances`,
 * `recordPhysicalCountItem` and `releaseReservation` (CRAP 42 each).
 */
describe('inventory CRAP-42 controllers', () => {
  let cookie = '';

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('getStockBalances', () => {
    const get = (query: Record<string, string> = {}) =>
      request(app)
        .get('/api/inventory/stock-balances')
        .set('Cookie', cookie)
        .query(query);

    it('returns a paginated balance list with defaults', async () => {
      const spy = jest
        .spyOn(StockMovementModel, 'getStockBalances')
        .mockReturnValue({
          rows: [{ item_id: 1 }],
          total: 2,
          pageNum: 1,
          limitNum: 10,
        } as unknown as ReturnType<typeof StockMovementModel.getStockBalances>);

      const res = await get();

      expect(res.status).toBe(200);
      expect(res.body).toEqual({
        success: true,
        data: [{ item_id: 1 }],
        pagination: {
          currentPage: 1,
          totalPages: 1,
          totalItems: 2,
          hasNext: false,
          hasPrev: false,
        },
      });
      expect(spy).toHaveBeenCalledWith(
        {
          search: undefined,
          warehouse_code: undefined,
          sortBy: undefined,
          sortOrder: undefined,
          page: 1,
          limit: 10,
        },
        expect.anything(),
      );
    });

    it('passes search, warehouse and sort filters', async () => {
      const spy = jest
        .spyOn(StockMovementModel, 'getStockBalances')
        .mockReturnValue({
          rows: [],
          total: 0,
          pageNum: 2,
          limitNum: 5,
        } as unknown as ReturnType<typeof StockMovementModel.getStockBalances>);

      await get({
        search: 'widget',
        warehouse_code: 'WH-1',
        sortBy: 'quantity',
        sortOrder: 'ASC',
        page: '2',
        limit: '5',
      });

      expect(spy).toHaveBeenCalledWith(
        {
          search: 'widget',
          warehouse_code: 'WH-1',
          sortBy: 'quantity',
          sortOrder: 'ASC',
          page: 2,
          limit: 5,
        },
        expect.anything(),
      );
    });

    it('returns a sanitized 500 when the balance read fails', async () => {
      jest.spyOn(logger, 'error').mockImplementation(() => logger);
      jest
        .spyOn(StockMovementModel, 'getStockBalances')
        .mockImplementation(() => {
          throw new Error('forced');
        });

      const res = await get();
      expect(res.status).toBe(500);
      expect(res.body).toEqual({ error: 'Failed to fetch stock balances' });
    });
  });

  describe('recordPhysicalCountItem', () => {
    const post = (body: Record<string, unknown>) =>
      request(app)
        .post('/api/inventory/physical-counts/9/items')
        .set('Cookie', cookie)
        .send(body);

    it('requires item id and counted quantity', async () => {
      expect((await post({})).status).toBe(400);
      const onlyItem = await post({ item_id: 1 });
      expect(onlyItem.status).toBe(400);
    });

    it('records an item and returns the updated row', async () => {
      const record = jest
        .spyOn(PhysicalCountModel, 'recordCount')
        .mockImplementation(() => {});
      jest.spyOn(PhysicalCountModel, 'getItems').mockReturnValue([
        { item_id: 1, counted_quantity: 5, notes: null },
      ] as unknown as ReturnType<typeof PhysicalCountModel.getItems>);

      const res = await post({ item_id: 1, counted_quantity: 5 });

      expect(res.status).toBe(200);
      expect(res.body).toEqual({ item_id: 1, counted_quantity: 5, notes: null });
      expect(record).toHaveBeenCalledWith(
        9,
        1,
        5,
        expect.any(Number),
        null,
        expect.anything(),
      );
    });

    it('returns a sanitized 500 when recording fails', async () => {
      jest.spyOn(logger, 'error').mockImplementation(() => logger);
      jest.spyOn(PhysicalCountModel, 'recordCount').mockImplementation(() => {
        throw new Error('forced count failure');
      });

      const res = await post({ item_id: 1, counted_quantity: 2 });
      expect(res.status).toBe(500);
      expect(res.body).toEqual({ error: 'forced count failure' });
    });

    it('falls back to a generic message when the failure has no text', async () => {
      jest.spyOn(logger, 'error').mockImplementation(() => logger);
      jest.spyOn(PhysicalCountModel, 'recordCount').mockImplementation(() => {
        throw '';
      });

      const res = await post({ item_id: 1, counted_quantity: 2 });
      expect(res.status).toBe(500);
      expect(res.body).toEqual({ error: 'Failed to record count' });
    });
  });

  describe('releaseReservation', () => {
    const release = () =>
      request(app)
        .delete('/api/inventory/reservations/7/release')
        .set('Cookie', cookie);

    it('returns 404 for an unknown reservation', async () => {
      jest.spyOn(StockReservationModel, 'getById').mockReturnValue(undefined);
      expect((await release()).status).toBe(404);
    });

    it('returns 400 when the reservation is not active', async () => {
      jest
        .spyOn(StockReservationModel, 'getById')
        .mockReturnValue({
          id: 7,
          reference_doctype: 'INVOICE',
          reference_docno: 'INV-1',
          reference_line_id: 1,
          batch_id: null,
          location_id: null,
        } as unknown as ReturnType<typeof StockReservationModel.getById>);
      jest
        .spyOn(StockReservationModel, 'release')
        .mockReturnValue(null as unknown as ReturnType<
          typeof StockReservationModel.release
        >);

      expect((await release()).status).toBe(400);
    });

    it('releases an active reservation', async () => {
      jest
        .spyOn(StockReservationModel, 'getById')
        .mockReturnValue({
          id: 7,
          reference_doctype: 'INVOICE',
          reference_docno: 'INV-1',
          reference_line_id: 1,
          batch_id: null,
          location_id: null,
        } as unknown as ReturnType<typeof StockReservationModel.getById>);
      const released = { id: 7, status: 'released' };
      jest
        .spyOn(StockReservationModel, 'release')
        .mockReturnValue(released as ReturnType<typeof StockReservationModel.release>);

      const res = await release();
      expect(res.status).toBe(200);
      expect(res.body).toEqual(released);
    });

    it('restores the batch/location reserved and available quantities', async () => {
      const item = db
        .prepare(`INSERT INTO items (item_code, item_name) VALUES ('REL-ITEM', 'Release Item')`)
        .run();
      const warehouse = db
        .prepare(
          `INSERT INTO warehouses (warehouse_code, warehouse_name) VALUES ('REL-WH', 'Release WH')`
        )
        .run();
      const batch = db
        .prepare(
          `INSERT INTO stock_batches
             (batch_no, item_id, warehouse_id, source_type, source_id,
              quantity_original, quantity_remaining, unit_cost, received_date)
           VALUES ('REL-BATCH', ?, ?, 'PURCHASE', 1, 10, 10, 5, '2026-01-01')`
        )
        .run(item.lastInsertRowid, warehouse.lastInsertRowid);
      const location = db
        .prepare(
          `INSERT INTO locations (warehouse_id, location_code, location_name)
           VALUES (?, 'REL-LOC', 'Release Location')`
        )
        .run(warehouse.lastInsertRowid);
      db.prepare(
        `INSERT INTO batch_stock_by_location
           (batch_id, location_id, quantity_physical, quantity_reserved, quantity_available)
         VALUES (?, ?, 10, 3, 7)`
      ).run(batch.lastInsertRowid, location.lastInsertRowid);

      jest
        .spyOn(StockReservationModel, 'getById')
        .mockReturnValue({
          id: 7,
          reference_doctype: 'INVOICE',
          reference_docno: 'INV-1',
          reference_line_id: 1,
          batch_id: batch.lastInsertRowid,
          location_id: location.lastInsertRowid,
          quantity_reserved: 2,
        } as unknown as ReturnType<typeof StockReservationModel.getById>);
      jest
        .spyOn(StockReservationModel, 'release')
        .mockReturnValue({ id: 7, status: 'released' } as ReturnType<
          typeof StockReservationModel.release
        >);

      expect((await release()).status).toBe(200);

      const row = db
        .prepare(
          `SELECT quantity_reserved, quantity_available FROM batch_stock_by_location
           WHERE batch_id = ? AND location_id = ?`
        )
        .get(batch.lastInsertRowid, location.lastInsertRowid) as {
        quantity_reserved: number;
        quantity_available: number;
      };
      expect(row).toEqual({ quantity_reserved: 1, quantity_available: 9 });
    });

    it('returns a sanitized 500 when the release fails', async () => {
      jest.spyOn(logger, 'error').mockImplementation(() => logger);
      jest.spyOn(StockReservationModel, 'getById').mockImplementation(() => {
        throw new Error('forced release failure');
      });

      const res = await release();
      expect(res.status).toBe(500);
      expect(res.body).toEqual({ error: 'forced release failure' });
    });
  });
});
