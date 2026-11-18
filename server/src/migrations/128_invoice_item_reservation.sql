-- S-1: persist the invoice-line -> stock_reservations link.
--
-- The sale now consumes the reservation it fulfils (Gull's Option B), but the
-- link lived only in the request body. Audit and reversal could not
-- reconstruct which reservation a line consumed, so a void/return had no way
-- to release the right reservation again.
--
-- Nullable on purpose: every historical invoice line predates this link and
-- stays NULL. The stock path treats NULL as "this line fulfilled no
-- reservation" — the pre-S-1 behaviour — so no backfill is correct and no
-- historical row is touched.
--
-- No FK: stock_reservations rows are appended and a consumed reservation is
-- kept (status CONSUMED), so the id stays valid, but an FK would block the
-- legacy NULLs and add no value here.

ALTER TABLE invoice_items ADD COLUMN reservation_id INTEGER;
