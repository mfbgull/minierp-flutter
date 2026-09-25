-- TASK 26: 'Other' is not a supported payment-account key (isValidPaymentMethod
-- rejects it; it would land in unclassified while GL mapped it to Bank).
-- Remap leftover expense rows to Cash so edits remain valid.
UPDATE expenses SET payment_method = 'Cash'
WHERE payment_method IS NOT NULL AND TRIM(payment_method) = 'Other';
