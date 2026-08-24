# reporting-search-remediation

Remediates the verified findings of the
reporting/global-search/duplicated-business-logic audit
(`opus5-audit-report/reports.md`): the GL becomes the single accounting
truth for the balance sheet, trial balance and cash views (with a
one-time backfill of pre-posting documents); revenue, COGS and tax get
single shared definitions across all report sites; the general ledger,
customer statements and period defaults are corrected; global search
gains row-level module read permissions with status hygiene and a flat
permission lookup; ~17 unrouted dead report functions are deleted; and
the unusable leading-wildcard search indexes are dropped.

Four audit findings were already remediated by in-flight work and are
out of scope: SRCH-01, REP-06, REP-15, REP-18.

Docs: [spec deltas](specs) · [proposal.md](proposal.md) · [design.md](design.md) · [tasks.md](tasks.md)
