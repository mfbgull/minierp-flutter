## ADDED Requirements

### Requirement: invoice-return-menu
Users can initiate a return from an invoice using a 3-dot menu action.

#### Scenario: return from invoice list
- **WHEN** a user opens the 3-dot menu on an invoice
- **THEN** a Return option is available and routes to invoice return creation for that invoice

### Requirement: invoice-detail-return
Users can initiate a return from the invoice detail view.

#### Scenario: return from invoice detail
- **WHEN** a user is viewing invoice detail
- **THEN** a return action is available and routes to invoice return creation for that invoice
