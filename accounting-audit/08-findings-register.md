# Findings register

Status: IN PROGRESS. Severity and evidence are reviewed before finalization. No production correction is implemented.

| ID | Status | Severity | Proven issue | Evidence |
|---|---|---|---|---|
| F-020 | Confirmed defect | High | Carried salary advance remains an asset after the following salary period is marked paid; salary expense understated | [Finding](findings/F-020/finding.md) |
| F-021 | Confirmed defect | High | Employee repayment accepted before loan disbursement; historical loan receivable becomes negative | [Finding](findings/F-021/finding.md) |
| F-040 | Confirmed defect | Medium | Balance-sheet screen omits nonzero categories while totals include them | Pending final folder integration |
| F-041 | Confirmed defect | Medium | Unquoted grouped currency splits a CSV monetary cell into multiple columns | Pending final folder integration |

Candidates under investigation are not counted as confirmed here. The query-granularity demonstration in `evidence/invariant-granularity.md` is a test-coverage limitation rather than a demonstrated production financial corruption path.
