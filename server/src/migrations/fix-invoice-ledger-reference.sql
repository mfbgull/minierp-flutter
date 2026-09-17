-- Fix invoice ledger entries with empty reference_no
-- This migration updates INVOICE entries in customer_ledger that have empty
-- or NULL reference_no by extracting the invoice number from the description.
-- For entries with "Invoice undefined" in the description, we match them to
-- invoices by customer_id and transaction_date.

-- Step 1: Update entries where description contains an invoice number
UPDATE customer_ledger
SET reference_no = SUBSTR(description, 9)
WHERE transaction_type = 'INVOICE'
  AND (reference_no IS NULL OR reference_no = '')
  AND description LIKE 'Invoice INV-%';

-- Step 2: Update entries with "Invoice undefined" by matching to invoices
-- This handles the case where invoice_no was not provided
UPDATE customer_ledger
SET 
  reference_no = (
    SELECT i.invoice_no 
    FROM invoices i 
    WHERE i.customer_id = customer_ledger.customer_id 
      AND i.invoice_date = customer_ledger.transaction_date
    ORDER BY i.id ASC
    LIMIT 1
  ),
  description = 'Invoice ' || (
    SELECT i.invoice_no 
    FROM invoices i 
    WHERE i.customer_id = customer_ledger.customer_id 
      AND i.invoice_date = customer_ledger.transaction_date
    ORDER BY i.id ASC
    LIMIT 1
  )
WHERE transaction_type = 'INVOICE'
  AND (reference_no IS NULL OR reference_no = '')
  AND description = 'Invoice undefined';
