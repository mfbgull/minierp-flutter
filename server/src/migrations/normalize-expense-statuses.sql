-- TASK 25 Option A: collapse legacy expense workflow statuses.
-- Submitted / Approved / Paid all post the same GL entry (cash effect on
-- leave-Draft); rename them to Recorded so status matches accounting.
-- Cash timing is unchanged: Draft still has no GL; Recorded is GL-worthy.
UPDATE expenses SET status = 'Recorded' WHERE status IN ('Submitted', 'Approved', 'Paid');
