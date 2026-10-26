# Remediation roadmap — proposal only

Production fixes, accounting-policy changes, historical corrections and deployment require separate authorization. The order below follows proven financial risk and dependencies.

| Order | Work | Required behavior / evidence before acceptance |
|---|---|---|
| 1 | F-002 credit entitlement and F-073 real tender | Prevent consumed credit reversal/reissue while downstream uses remain active. Independently preserve explicit zero POS cash and reject insufficient tender before posting; do not default numeric0 to invoice total. Both critical detectors must become green, with correct real cash, receivables, stock and retry behavior |
| 2 | F-025 partial count correction and F-024 layer provenance | Preserve every unaffected item's valid shortage, or reject incomplete replacement before mutation. Persist/restore exact consumed layers; never relax batch bounds. Mixed5@10+5@20 recount and two-item partial correction must reconcile quantity, GL, cost layers, loss and audit lineage |
| 3 | F-022 integer cost apportionment | Allocate integer minor-unit pool with nonnegative shares and exact conservation. Do not hide a negative residual with a posting skip/clamp. Test tiny pool, many outputs, differing sales bases, zero-price fallback, positive overhead and cancellation; clearing zero and inventory GL=valid batches |
| 4 | F-020 salary advance recognition | When earned carryover settles a later salary, reclassify advance asset to that period's salary expense exactly once; no additional cash. Reversal must restore the advance and original expense correctly. Assert two periods' expense2000, advance0, cash2000 and report propagation |
| 5 | F-001/F-021 shared source chronology | Apply source-date lower bounds to sales returns, purchase returns and direct loan repayment as well as existing sale/payroll deduction paths. Reject invalid chronology atomically and preserve open/closed period controls. Test daily/month/year boundaries, GL and subledger dating separately |
| 6 | F-040/F-042 financial UI completeness | Preserve/render/export all nonzero balance-sheet categories; explain rows so totals reconcile. Use authoritative salary remaining800, counting advance once. Mounted valid-API fixtures plus real API reload must agree |
| 7 | F-043 report expense breakdown and F-041 CSV | Reconcile GL expenses to category detail without double count; include losses/payroll/accruals or disclose narrower scope with a reconciling remainder. Use shared CSV escaping for every row/header and a real CSV parser in regressions |
| 8 | F-023 policy disposition and unsupported supplier split | Resolve D15 before altering closed-period guards. Separately decide whether return-credit-to-purchase allocation is required; current500 must become a controlled unsupported/validation response even without adding the feature. Do not model a no-cash credit application as a new payment |
| 9 | Close independent verification gaps | Execute remaining POS/mobile/SO/quotation, count-location branches, supplier advances, all reversals, positive overhead settlement, cash wallets/transfers, tax/discount/aging boundaries, custom reports, print/export and native Flutter reload flows |
| 10 | Strengthen evidence gates | Add per-entry balance and signed AR reconciliation, positive fixtures for each extended invariant, exact source/consumption linkage and report-detail-to-total checks. Separate detector tests that expect correct behavior from forensic verifiers that intentionally assert a captured defect |

Additional controls: F-071/F-072 require one atomic reservation/location primitive, replay-safe quantity deltas and NULL-aware identity/release. F-060 requires consistent header/line void lineage without affecting unrelated active lines. F-070 requires controlled invalid-state4xx while preserving its already-correct no-mutation guard. Reservation availability, header audit state and error taxonomy should be regressed separately from money totals.

## Regression and rollout discipline

- Start each authorized fix with the independent failing detector; preserve red evidence before applying it. Some forensic audit verifiers exit0 because they prove the bad state exists; those are not permanent passing correctness tests.
- Run affected/dependent accounting tests and A–J plus signed/entry-level checks after each fix. Run full affected-side suites and shared contracts at phase completion; do not weaken valid tests or change production policies to obtain green results.
- Keep schema changes in registered migrations. Verify migration behavior on disposable DBs before considering deployment.
- Investigate any possible real affected records only under a separately authorized, read-only assessment first. Preserve consistent originals/WAL state and audit lineage. No automatic historical rewrite, balancing plug or silent repair is authorized by this report.
- Release acceptance requires the critical entitlement exploit closed, high-risk economic reconciliations green, policy dispositions explicit and remaining coverage accepted. A balanced trial balance or green existing suite alone is insufficient.
