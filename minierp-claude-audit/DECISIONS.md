# MiniERP: Finalized Seven Decisions

Decision record for implementation

The following records the seven decisions agreed for the current MiniERP work. The implementation should follow these decisions and preserve existing accounting, inventory, and authorization integrity.

## D1 — Require funds for cash purchases, salary and loans?

**Reference:** ACCT-005, PAY-003

- Yes. Cash purchases, salaries, loan payments and other cash outflows must validate sufficient available funds before posting.
- Record opening cash or owner capital first when those funds genuinely exist.
- Fix the 12 affected fixture suites using one shared helper that seeds opening cash; do not weaken production validation to make tests pass.

## D2 — Block reversals of cash inflows that would overdraw cash?

**Reference:** ACCT-013

- Yes. Reject capital edits/voids and receipt deletions or reversals when they would make the affected cash/bank account negative on a later date.
- Show the message: “Reverse the later spending first.” Identify the affected later transactions where practical.
- Check chronological account balances, not only the current balance. Do not allow unauthorized negative cash balances; bank overdrafts require explicit configuration and an approved limit.
- Preserve posted financial records through an auditable correction or reversal process.

## D3 — Salary overpayment model

**Reference:** PAY-001 / PAY-002

- Post once. Split one payment into a current-month salary row (up to the remaining earned salary) and an employee-advance row for the excess.
- The two rows must total exactly the amount paid, link the advance to its parent, and be voided together.
- Record the excess as an employee advance/receivable; do not recognize it as salary expense a second time.

## D4 — Salary-deduction loan repayments

**Reference:** PAY-004

- Post Dr Cash / Cr account 1300, following the agreed direct-repayment model.
- This assumes account 1300 is the employee-loan receivable account and the salary row has already been posted at gross cash. Confirm the account mapping in the chart of accounts.
- Ensure the combined salary and repayment entries represent the actual net cash paid and the reduction in the employee loan balance.

## D5 — Permissions that guard routes but do not exist

**Reference:** AUTHZ-001 / AUTHZ-004

- Seed all 14 missing permission codes into the permissions table so roles can be granted them through the roles screen. Grant none by default.
- Rename inventory:write to inventory:update and update all references consistently.
- Seed admin:* and owner_equity:* as sensitive permissions.
- Retain the AUTHZ-004 rule: non-admins must not grant permissions they do not themselves possess.

## D6 — Production overhead accounting

**Reference:** PROD-001

- Include production overhead directly attributable to manufacturing in production cost because it affects unit cost.
- Allocate applicable overhead using a consistent, documented method; include it in work-in-progress/finished-goods valuation and recognize it through COGS as the products are sold.
- General administrative expenses not attributable to production remain period expenses. Do not expense the same overhead twice.
- Define a defensible joint-cost allocation between mustard oil and mustard cake and keep production records, inventory valuation, the general ledger and COGS consistent.

## D7 — Back up uploads and allow damaged-stock write-offs?

**Reference:** Backup / inventory write-off

- Yes. Include server/uploads/ alongside each corresponding database backup, with a clear association between the database snapshot and uploaded files.
- Yes. Allow damaged-stock write-offs through the existing write-off flow, requiring a reason code and an auditable record.
- Use account 7201 if it is the correct existing write-off expense account; otherwise, define a dedicated account such as 7202 after checking the chart of accounts.

**Implementation note:** The business decisions above are finalized. Verify account mappings and existing-code dependencies before implementation; do not silently change the agreed accounting behavior.
