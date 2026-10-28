# MiniERP: verify and repair accounting audit findings

Work in `/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter`.

Act as a senior accounting-systems engineer responsible for financial correctness across Node/SQLite, Flutter, operational subledgers and financial reports. Address me as Gull in every reply.

Your assignment is to **verify which audit findings are already fixed, implement the remaining confirmed fixes, and prove the resulting accounting behavior independently**. This authorizes necessary production-source changes and regression tests in this repository. It does not authorize modifying real financial data, changing accounting policies, committing, pushing or deploying.

Do the work through verification and reporting. Do not stop after proposing a plan, finding the first defect or obtaining a green existing suite.

## 1. Establish the current state

Read applicable AGENTS.md files, CODING_STANDARDS.md, docs/REVERSAL-RULES.md, relevant accounting/API specifications, audit/DECISIONS.md, audit/FINDINGS-STATUS.md and the accounting-audit findings, coverage, workstreams and remediation roadmap. Consult archive references where the live ledgers point to them.

Prefer the codebase-memory graph for code discovery; check coverage and use direct-source fallback where necessary. Derive actual routes, schema, account mappings and calculations from current source.

Inspect the working tree and preserve all existing edits. Audit reports describe historical snapshots: **do not assume a finding remains open because an old report says FAIL or release blocked**. Conversely, a FIXED label or commit message alone is not proof.

Create `accounting-audit/remediation/STATUS.md` with one row per finding:

`ID | current classification | source/root cause | fixing commit or working-tree change | regression test | executed verification/evidence | remaining limitation`

Use: VERIFIED FIXED, REPRODUCED OPEN, POLICY DECISION REQUIRED, UNSUPPORTED WORKFLOW, NOT REPRODUCED, or UNVERIFIED. NOT REPRODUCED is not automatically VERIFIED FIXED.

## 2. Prioritize financial risk

Start with F-002 consumed-credit reuse and F-073 explicit-zero POS tender. Then address stock counts/valuation F-025/F-024/F-022, salary and chronology F-020/F-001/F-021, reservations F-071/F-072, journal audit status F-060, presentation/export F-040–043 and error classification F-070.

Revalidate this ordering against current status; do not reapply an existing correct fix. Review any additional current findings recorded in the ledgers.

F-023 and closed-period settlement require the current decision log, including D15 or a later superseding decision. Do not silently choose a policy. Document a genuine unresolved product/accounting decision, ask one focused question only when necessary, and continue independent fixes while it remains open. Do not invent an unimplemented supplier-credit allocation or other product feature merely to make an audit scenario pass.

## 3. Prove each remaining defect before fixing it

For every open defect:

1. Derive expected results from economic events using integer minor units or precise decimal arithmetic. Do not use the application's own calculation as the expected-value oracle.
2. Write a durable regression test and watch the relevant assertion fail before changing production code.
3. Trace the source invariant and all affected callers. Make the smallest complete fix at the shared boundary, rather than adding a guard to only one caller.
4. Observe the test pass, then exercise dependent workflows and reports.

For already-fixed behavior, inspect the actual implementation and execute the relevant regression and an independent scenario. If testing a historical bad version is useful, use a disposable isolated checkout; never revert or mutate the shared working tree. If red-baseline evidence cannot be recovered, state that limitation instead of inventing it.

Some audit scripts intentionally assert that an observed bad state exists and therefore exit successfully when the defect is present. Those are forensic verifiers, **not passing correctness regressions**. Promote tests that expect correct behavior into the normal test suites where appropriate; retain the historical evidence.

## 4. Accounting acceptance criteria

Verify as applicable to each fix:

- Real cash tender governs receipts. Credit application is not new cash, revenue or a second entitlement.
- Consumed credits cannot regenerate through void/reissue, retries or another allocation path.
- Quantity and valuation reconcile across movements, batches, locations, documents and inventory GL. Count corrections preserve unaffected items and restore exact cost layers.
- Production allocations are nonnegative, conserve the cost pool exactly and leave clearing neutral; attributable overhead is recognized once and reversal restores original effects.
- Salary carryover becomes earned salary expense exactly once; it is neither cash paid twice nor subtracted twice in Flutter.
- Source-linked returns/repayments respect the documented chronology and period policy, including historical report effects.
- Reservation replay/release changes location availability exactly once and handles optional identifiers consistently.
- Header/line void status and audit attribution agree without voiding unrelated active lines or deleting financial history.
- API, database, subledger, GL, displayed detail, report totals and exports agree with the independent economic oracle. Verify signs, dates, rounding and labels.

Run A–J and relevant extended checks, but also independently check **each journal entry**, **signed AR/credit balances**, and economic recognition. Reference-group balancing and absolute-value comparisons alone can miss defects.

## 5. Safety and scope

- Use fresh disposable databases with explicit paths set before application/database imports. Inspect path semantics and install a guard preventing any accidental live database write.
- Never run destructive scenarios or migrations against real business data. Do not repair historical records or insert balancing plugs.
- Treat documented dummy legacy gaps as known noise; isolate new tests with clean fixtures without weakening integrity checks.
- Verify required migrations on disposable databases, register them through the existing mechanism and preserve auditability.
- Do not weaken/delete/skip valid tests, disable invariants, suppress diagnostics, or change CI gates/baselines merely to obtain green results.
- Avoid unrelated refactors, dependency upgrades and UI redesign. Preserve audit evidence, active audit baselines, decisions and regression tests.

## 6. Exercise the real interfaces

Backend fixes require actual mounted routes with realistic request bodies and assertions on committed or rolled-back SQL, GL and subledger effects. Test repeat submissions and affected reversal paths.

Flutter changes require mounted widgets driven by interactions and authoritative backend-shaped data. Where practical, execute the complete UI/API/reload flow. Inspect affected reports and exports after payment, return, allocation and reversal. Label static-only or unexecuted verification explicitly.

## 7. Verification and completion

Follow the repository's risk-based testing policy: targeted and dependent tests after each fix; accounting invariants for financial changes; relevant static checks at checkpoints; full suites for affected sides at phase completion. Use the documented commands, including `scripts/check.sh` where both sides/shared contracts are affected. Do not rerun an unchanged side solely out of habit.

Record exact commands, exit status, counts, source revision and limitations. Investigate failures and hanging/open-handle runs; partial output is not a clean successful command.

Before finishing, review the diff against every acceptance criterion. If collaboration tools are available, use a separate read-only reviewer for financial correctness and missed paths, then resolve material findings and rerun affected checks. Do not call self-review independent review.

Preserve original findings/raw evidence as historical records. Update current status ledgers and add dated resolution links/banners to obsolete summaries, so old release-blocking text cannot be mistaken for a current assessment. Store new evidence under `accounting-audit/remediation/`.

Finish with a concise report of verified existing fixes, new fixes, remaining policy/unsupported/unverified cases, exact tests/checks and failures, changed files and release-readiness limits. Do not claim comprehensive financial safety from tests alone. Stop when every in-scope finding has an evidence-backed disposition, all actionable fixes are implemented and checked, and any remaining external decision or verification limitation is explicit.
