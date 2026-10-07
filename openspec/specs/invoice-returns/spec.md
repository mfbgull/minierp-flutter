# Invoice Returns

## Purpose

Users can process customer returns from the invoice list 3-dot menu and from
the invoice detail/print-preview view. A return restocks the returned goods
into a warehouse chosen by the user, reverses the sale's stock/GL/ledger
effects and applies the disposition (refund, credit or adjust).

## Requirements

### Requirement: invoice-return-menu
An invoice's 3-dot menu SHALL offer a Return option that routes to invoice return creation for that invoice.

#### Scenario: return from invoice list
- **WHEN** a user opens the 3-dot menu on an invoice
- **THEN** a Return option is available and routes to invoice return creation for that invoice

### Requirement: invoice-detail-return
The invoice detail view SHALL offer a return action that routes to invoice return creation for that invoice.

#### Scenario: return from invoice detail
- **WHEN** a user is viewing invoice detail
- **THEN** a return action is available and routes to invoice return creation for that invoice

### Requirement: invoice-return-restock-warehouse
A customer return SHALL require the user to select a restock warehouse, and the server SHALL restock the returned items into that warehouse.

#### Scenario: restock warehouse is required
- **WHEN** a user processes a return on an invoice
- **THEN** the return form requires a restock warehouse and the server restocks the returned items there
