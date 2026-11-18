-- S-1 fix (GLM HIGH): a PARTIAL sale must keep enough per-bin history for a
-- later void to restore the ORIGINAL allocation.
--
-- Before this column, `quantity_reserved` on a child row was both "what this
-- bin still owes" and "what this bin was allocated". A partial consume had to
-- shrink it to the remainder, so once a bin was fully drained the original
-- amount was gone: voiding the sale restored the header to the pre-sale total
-- but could only put back the bins that still had a non-zero remainder.
--
-- `quantity_allocated` is the durable original allocation. `quantity_reserved`
-- keeps its existing meaning (the current remainder that a sale may drain), so
-- every existing reader is unaffected.
--
-- Backfill: existing rows are mid-flight, so their current remainder is the
-- best available record of what they were allocated; new rows write both
-- columns explicitly.
ALTER TABLE stock_reservation_bins ADD COLUMN quantity_allocated DECIMAL(15,3);
UPDATE stock_reservation_bins SET quantity_allocated = quantity_reserved WHERE quantity_allocated IS NULL;
