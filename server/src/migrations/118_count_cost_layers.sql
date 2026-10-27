CREATE TABLE physical_count_layers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  movement_id INTEGER NOT NULL REFERENCES stock_movements(id),
  batch_id INTEGER REFERENCES stock_batches(id),
  location_id INTEGER REFERENCES locations(id),
  quantity REAL NOT NULL CHECK(quantity > 0),
  unit_cost REAL NOT NULL CHECK(unit_cost >= 0)
);
CREATE INDEX idx_physical_count_layers_movement ON physical_count_layers(movement_id);
