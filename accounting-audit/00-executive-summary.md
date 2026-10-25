# MiniERP accounting integrity audit

Status: IN PROGRESS. This is an audit, not authorization to repair or release.

Scope: the repository at the recorded source revision, fresh disposable databases, financial APIs, reports, and Flutter presentation. No production database will be migrated, modified, or used for destructive scenarios. Existing dummy historical accounting gaps are outside scope unless current logic reproduces them.

The audit separates economic correctness, database consistency, report correctness, UI presentation, and business-policy correctness. A passing existing suite is supporting evidence only.

Workstreams:

1. Independent economic-event oracle and lifecycle/API/database reconciliation.
2. Backend recognition, schema, migrations, controls, reversals, inventory, payroll, equity, and production.
3. Flutter financial sources, formulas, state, reports, exports, and executed widget checks.
4. Leader verification, cross-module synthesis, and independent adversarial challenge.

The final module and figure matrices will explicitly retain PARTIAL and NOT TESTED results. Release readiness is unassessed pending execution and evidence review.

See [coverage](03-coverage-matrix.md), [scenario plan](05-test-scenarios.md), and [limitations](07-unverified-areas.md).
