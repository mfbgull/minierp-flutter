# Findings register

**16 confirmed defects: 2 Critical, 6 High, 7 Medium, 1 Low.** One separately observed behavior requires an accounting-policy decision and is excluded from those counts. No fix or financial repair was implemented by this audit. Severity follows proven impact; a failed request that rolls back is not described as committed corruption. Later unrelated working-tree edits are preserved; the findings state their executed snapshot and revalidation limits.

| ID | Status | Severity | Proven result | Finding / reproducible evidence |
|---|---|---|---|---|
| F-002 | Confirmed defect | Critical | Consumed return credit60 can be voided, reissued and spent again. Correct economic/GL receivable75; operational receivable15, undercollection60 | [Finding](findings/F-002/finding.md), clean dedicated z9sfxV fixture |
| F-073 | Confirmed defect | Critical | Explicit POS cash_received0 fabricates17.35 Cash payment, marks paid and releases stock9.25 | [Finding](findings/F-073/finding.md), AFjr5O API/SQL and independent proof |
| F-001 | Confirmed defect | High | Sales and purchase returns accepted before source transactions; historical inventory/revenue/COGS/AP move before acquisition/sale | [Finding](findings/F-001/finding.md), AbsZeT and ZHkdJ8 fixtures |
| F-020 | Confirmed defect | High | Carried salary advance remains asset200 after both periods marked paid; salary expense/profit wrong200 | [Finding](findings/F-020/finding.md), Lbw3la fixture |
| F-021 | Confirmed defect | High | Repayment accepted before loan disbursement; dated loan asset−200 before it exists | [Finding](findings/F-021/finding.md), Lbw3la fixture |
| F-022 | Confirmed defect | High | Joint production pool0.02 creates output cost−0.01, GL inventory0.03 vs batch0.02 and clearing−0.01 | [Finding](findings/F-022/finding.md), Lbw3la fixture |
| F-024 | Confirmed defect | High | Valid mixed-layer count correction500; batch constraint prevents invalid restoration and transaction rolls back | [Finding](findings/F-024/finding.md), ZBybHv fixture; serious correction workflow failure, no committed mutation |
| F-025 | Confirmed defect | High | Correcting one count item erases omitted item's valid shortage: inventory+20, expense−20 despite unchanged posted-count row | [Finding](findings/F-025/finding.md), ZBybHv fixture |
| F-040 | Confirmed defect | Medium | Typed model/screen/CSV omit other assets400, tax60 and other liabilities70 while retaining correct aggregate totals | [Finding](findings/F-040/finding.md), mounted widget/text/image |
| F-041 | Confirmed defect | Medium | Actual CSV currency1,000 splits into extra cell; quote-aware parser confirms malformed export | [Finding](findings/F-041/finding.md), actual export and targeted detector |
| F-042 | Confirmed defect | Medium | Salary dialog subtracts already-included carryover twice: remaining600 vs authoritative800 | [Finding](findings/F-042/finding.md), actual backend financial fields replayed in widget |
| F-043 | Confirmed defect | Medium | P&L expense rows10 fail to explain total20; damage10 missing from breakdown, profit50 remains correct | [Finding](findings/F-043/finding.md), actual retail API/widget |
| F-060 | Confirmed defect | Medium | Nine active headers have all child lines voided; canonical balances still correct | [Finding](findings/F-060/finding.md), GIxBh2 retained DB |
| F-071 | Confirmed defect | Medium | Retrying one3-unit reservation reserves6 at location; release leaves phantom3 | [Finding](findings/F-071/finding.md), AFjr5O and positive control |
| F-072 | Confirmed defect | Medium | Accepted reservation with optional line ID omitted cannot release; reserved2 remains | [Finding](findings/F-072/finding.md), AFjr5O |
| F-070 | Confirmed defect | Low | Repeated SO cancel returns500, state correctly unchanged | [Finding](findings/F-070/finding.md), AFjr5O hash/status proof |
| F-023 | Accounting-policy decision required | Medium priority; not counted as corruption | Closing accrual period blocks later open-period expense/bill settlement409; no payment posts | [Finding](findings/F-023/finding.md), decision D15 in [decision log](../audit/DECISIONS.md) |

Each finding contains reproduction, independent expected/actual accounting, financial impact, actual source references, retained DB/API or widget/export evidence, root cause, recommended correction and regression requirements. UI-only findings do not claim a new underlying database corruption.

## Other explicit dispositions

| Item | Status | Evidence-based disposition |
|---|---|---|
| Historical D12 pre-receipt sale allocator concern | Expected behavior for new bounded probe | Current sale is rejected atomically; older current-stock-only description is stale |
| Supplier return-credit split across purchases | Unable to verify successful workflow / unsupported in inspected public implementation | Actual two-target request returns500 and changes nothing; aggregate AP15 is correct. A supplier-prepayment feature is not substituted for return credit |
| Mandatory invoice idempotency key | Accounting/product compatibility decision remains unresolved | Keys work when supplied; absent external mobile client prevents verifying mandatory-key compatibility |
| Invariant A grouping / F absolute signs | Confirmed check-coverage limitations | Independent synthetic examples; not counted as production transaction corruption findings |
| Existing dummy historical discrepancies | Excluded known legacy noise | No repeated historical audit, repair or mutation performed |

Earlier fixture mistakes and superseded expectations are disclosed in the workstreams. They are not findings. The independent adversarial reviews validate bounded evidence; they do not certify unexecuted workflows.
