-- New counts retain the original surplus valuation basis independently of
-- actual shortage-layer cost. Leave historical rows untouched.
ALTER TABLE physical_count_items ADD COLUMN snapshot_unit_cost REAL;
