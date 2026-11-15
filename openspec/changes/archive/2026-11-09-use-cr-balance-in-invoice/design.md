## Context

Customers may carry credit balances (CR) from overpayments, returns, or adjustments. Currently, these credits are tracked in the system but not automatically applied during invoice creation. Users must manually track credits and create separate payment entries, leading to inefficiency and potential for lost credits.

The invoice creation flow currently handles direct payments only. We need to extend this to optionally apply existing customer credits before prompting for payment of any remaining balance.

## Goals / Non-Goals

**Goals:**
- Display customer's available CR balance during invoice creation
- Allow applying CR balance to current invoice
- Handle partial or full credit application with proper accounting
- Ensure remaining balance is collected via normal payment methods

**Non-Goals:**
- Modifying how CR balances are initially created (handled by returns, adjustments)
- Creating new payment methods or payment gateways
- Modifying existing credit reporting or balance statements
- Bulk credit application across multiple invoices

## Decisions

### 1. Credit Balance Display Location
**Decision**: Show CR balance on the invoice creation form after customer selection.

**Rationale**: Provides immediate visibility of available credit at the point of invoice creation, enabling informed decisions without navigating away.

**Alternatives Considered**:
- Separate "Check Credit" button - adds unnecessary clicks
- Customer detail page only - requires context switching

### 2. Credit Application Trigger
**Decision**: Add "Apply Credit" checkbox with optional amount input field.

**Rationale**: Checkbox provides clear intent to use credit. Amount field allows partial application. Defaults to full credit or invoice amount (whichever is less).

**Alternatives Considered**:
- Auto-apply all credits - may not be desired in all cases
- Radio buttons for full/partial - less flexible

### 3. Payment Flow Integration
**Decision**: After credit application, remaining balance flows into existing payment collection.

**Rationale**: Reuses proven payment logic. Credit offset is recorded as a separate line item, then payment handles the remainder.

**Alternatives Considered**:
- Modified payment form - increases complexity and risk
- Separate credit payment method - adds unnecessary abstraction

### 4. Accounting Treatment
**Decision**: Credit application creates a debit to Customer Credit (asset reduction) and credit to the invoice AR (asset reduction).

**Rationale**: Maintains clean double-entry accounting. Credit balance is an asset (receivable from customer); applying it reduces both the credit balance and the new receivable.

**Alternatives Considered**:
- Net method - loses audit trail of credit usage
- Direct offset - complicates reconciliation

## Risks / Trade-offs

- **[Risk]** Credit application timing - if credits are applied after invoice posting, reconciliation issues occur. **Mitigation**: Process credit offset atomically with invoice creation.

- **[Risk]** Concurrent credit usage - two invoices applying same credit simultaneously. **Mitigation**: Use database transaction with credit balance validation before applying.

- **[Trade-off]** Simplicity vs flexibility - simple checkbox approach covers most cases but doesn't support complex scenarios like conditional credit application. Acceptable for current requirements.
