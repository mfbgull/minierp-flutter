## ADDED Requirements

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
