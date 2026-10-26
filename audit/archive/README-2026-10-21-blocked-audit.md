# ERP outside-in audit

## Executive summary

The audit is **blocked before application access**. The computer-use inventory returned `apps: []` and `browsers: []`; a follow-up request for `cua.listWindows()` failed because that method is unavailable in the exposed session. No ERP screen, business record, or report could be observed. No test transaction was attempted, and no accounting or inventory conclusion is made.

- Checks executed: 0
- Checks passed: 0
- Findings by severity: Critical 0, High 0, Medium 0, Low 0
- Scope checks blocked: see [coverage checklist](coverage_checklist.md)
- Top financial-impact findings: none observed; application was inaccessible
- Environment: Linux Mint as specified by the requester; audit date 2026-10-21; app version and binary hash unknown; device/emulator and workspace 3 surface unavailable to the active computer-use session
- Not tested: every product, inventory, purchase, sales, quotation, payment, party, warehouse, report, invariant, and permissions check in the checklist, because no application window or browser tab was exposed
- Evidence limitation: no target surface existed from which to capture application screenshots, recordings, report exports, stored data, network traffic, preferences, or binaries

The target must be made visible in the active computer-use session (workspace 3) before this audit can proceed. This package records the access blocker only; it is not an application audit result.

## Files

- `baseline/seed_data.md`: observed baseline and unavailable fixture inventory
- `baseline/baseline_screenshots/README.md`: why no baseline screenshot exists
- `coverage_checklist.md`: requested scope with explicit BLOCKED status
- `execution_log.jsonl`: append-only log of audit-surface observations
- `reports_exported/README.md`: why no report exports exist
- `findings/`: empty because no application behavior was observed
