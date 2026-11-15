# gl-posting-matrix (Delta)

## ADDED Requirements

### Requirement: Inventory movement and inventory accounting post exactly once per event
Each business event SHALL produce exactly one inventory financial effect. Goods
received post `Dr 1200`. A reversal of that receipt removes the posting; it does
not add one.

```
  create            Dr 1200 / Cr 2000        (Purchase.ts)
  void              void the group           (Purchase.ts)
                    movement: no leg         ← was posting a second Dr/Cr pair
  goods receipt     Dr 1200 / Cr 2000        (PurchaseOrder.ts)
  void              void the group, raw INSERT for stock (PurchaseOrder.ts — correct)
```

#### Scenario: A receipt and its void are net zero
- **WHEN** a purchase order receipt is created and then voided before any of its
  stock is consumed
- **THEN** GL 1200 and GL 2000 both return to their pre-receipt values

#### Scenario: The correct pattern already exists and is the reference
- **WHEN** `voidGoodsReceipt` reverses a receipt
- **THEN** it writes its stock movement with a raw INSERT and no financial leg,
  which is the shape `Purchase.void` now follows

### Requirement: Shrinkage is reserved for genuine loss
GL 7200 Inventory Shrinkage SHALL be posted only when inventory actually
disappears — damage, expiry, theft, a count correction downward. Voiding a
purchase or a return SHALL NOT post to it.

#### Scenario: Returning goods to a supplier is not a loss
- **WHEN** purchased goods are returned to the supplier
- **THEN** no shrinkage expense is recognised

#### Scenario: A count correction downward is still a loss
- **WHEN** a physical count finds less stock than recorded
- **THEN** the shortfall posts `Dr 7200 / Cr 1200` at the consumed layer's cost