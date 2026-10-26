# Supplier advance, expense payable and cash-count extension

Finalized from retained executed evidence by the lead after the worker's handoff was interrupted. No claim of additional unexecuted worker testing is made. No production code/database edits occurred.

Invocation: `node accounting-audit/tests/payable-cash-extension.cjs`. Fresh unique fixture with NODE_ENV=test, explicit directory DATABASE_PATH and constructor guard before application imports. Authoritative run: `evidence/payable-cash-run-GIxBh2`,41 mounted requests and552 assertions:535 pass,17 repeated header-consistency failures for F-060. All41 operations and final integrity checks were captured. The run's completed=false reflects red assertions, not a claim that the operation sequence stopped early.

| Bounded scenario | Independent economic result | Status |
|---|---|---|
| Supplier bill plus purchase | Bill115.29=expense100.25+input tax15.04; purchase49.36; total AP164.65 | PASS economic assertions |
| Supplier advance funding/replay | Cash200.75 leaves cash799.25 from1000; advance asset200.75; payable unchanged; replay retains source id | PASS |
| Apply advance80.24 | No cash movement; advance120.51/AP84.41 remain | PASS |
| Exact bill and purchase application/guards | Bill paid115.29/balance0; purchase AP29.25 remains; advance65.35. Over-application and consumed-source void blocked without mutation | PASS |
| Application reversal and advance void | Applications restore asset200.75/AP164.65 with no new cash; advance void restores funding; repeat void200 is economically neutral | PASS balances; FAIL header status F-060 |
| Unused Bank advance/void |25.25 funding then void restores Bank1000 | PASS balances; header inconsistency retained |
| Credit expense/partial/exact payment | Accrue120.37 without cash, pay40.12 leaves payable80.25, exact Bank payment80.25 settles; overpay/edit guards and replay tested | PASS balances; FAIL reversal header status |
| Expense payment void/cancel | Reversal and cancellation restore appropriate cash/liability/expense; repeated payment void200 changes nothing | PASS economic assertions; FAIL F-060 metadata |
| Injected GL failures | Advance/payment failed posting preserves full economic/source snapshot | PASS bounded atomicity |
| Opening seed replacement/count | Cash100.10/Bank50.20 opening seeds, repeat replacement, physical count shortage0.15 disclosed; unknown account rejects entire count atomically; seed reset tested | PASS expected balances/counts; FAIL F-060 header status |

The earlier hii4TA run passed464 checks before the header test was added. It is superseded for audit-store consistency; its green result cannot disprove F-060. One initial oN5SSD setup run is not product evidence.

No dedicated unused-advance cash-refund endpoint or cash-to-bank transfer/reversal route was established by the bounded route/source search. Unused advance void is not relabeled as a refund feature, and an opening seed is not a transfer.

Independent retained-DB verification: `node accounting-audit/tests/final-extension-verifier.cjs`, output `evidence/final-extension-verification.json`:9 active headers with all child lines void,0 unbalanced active journal groups, SQLite integrity/FK observations retained. Current canonical monetary balances agree with the independent oracle. No boot-induced duplicate money effect is claimed.
