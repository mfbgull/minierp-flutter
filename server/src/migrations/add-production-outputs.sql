-- D6: joint production. A single production can now yield several output
-- items (mustard oil + mustard cake), so the outputs live in their own table
-- instead of only in the productions header columns.
--
-- The header columns (output_item_id / output_quantity) keep the PRIMARY
-- (first) output so existing list, report and search queries stay valid;
-- every output - including that primary one - is also a row here.
CREATE TABLE IF NOT EXISTS production_outputs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    production_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    quantity DECIMAL(15,3) NOT NULL,
    -- unit cost derived from this row's allocated_cost / quantity
    unit_cost DECIMAL(15,6) DEFAULT 0,
    -- share of joint cost (materials + overhead) allocated by relative
    -- sales value; rows always sum to the production's total batch cost
    allocated_cost DECIMAL(15,2) DEFAULT 0,
    FOREIGN KEY (production_id) REFERENCES productions(id) ON DELETE CASCADE,
    FOREIGN KEY (item_id) REFERENCES items(id)
);

CREATE INDEX IF NOT EXISTS idx_production_outputs_production
    ON production_outputs(production_id);
CREATE INDEX IF NOT EXISTS idx_production_outputs_item
    ON production_outputs(item_id);

-- Backfill legacy single-output productions so read paths have exactly one
-- row per production regardless of when it was recorded. The allocated cost
-- is the batch valuation (quantity x unit cost), which is what the GL
-- debited to inventory for these rows.
INSERT INTO production_outputs
    (production_id, item_id, quantity, unit_cost, allocated_cost)
SELECT
    p.id,
    p.output_item_id,
    p.output_quantity,
    COALESCE(p.unit_cost, 0),
    ROUND(p.output_quantity * COALESCE(p.unit_cost, 0), 2)
FROM productions p
WHERE NOT EXISTS (
    SELECT 1 FROM production_outputs po WHERE po.production_id = p.id
);
