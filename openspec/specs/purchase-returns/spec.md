# Purchase Returns

## Purpose

Users can create purchase returns (against a direct purchase or a purchase
order) from the purchase return screen and from the source documents' row
menus. A return reduces stock from the source document's warehouse and, when
posted, creates the supplier credit note + GL reversal.

## Requirements

### Requirement: purchase-return-entry
Users can start a purchase return from the purchase return screen via a dedicated new-return action.

#### Scenario: new return from purchase return screen
- **WHEN** a user is on the purchase return screen
- **THEN** a new-return action is available and opens the purchase return entry flow

### Requirement: purchase-order-return-menu
Users can initiate a return from a purchase order using a 3-dot menu action.

#### Scenario: return from purchase order
- **WHEN** a user opens the 3-dot menu on a purchase order
- **THEN** a Return option is available and routes to purchase return creation for that order

### Requirement: purchase-return-menu
Users can initiate a return from a purchase using a 3-dot menu action.

#### Scenario: return from purchase
- **WHEN** a user opens the 3-dot menu on a purchase
- **THEN** a Return option is available and routes to purchase return creation for that purchase

### Requirement: purchase-return-source-warehouse
A purchase return reduces stock from the source document's warehouse — the warehouse is not user-selectable.

#### Scenario: warehouse is fixed to the source
- **WHEN** a user submits a return for a purchase or purchase order
- **THEN** stock is reduced in the source document's warehouse and the form shows it read-only
