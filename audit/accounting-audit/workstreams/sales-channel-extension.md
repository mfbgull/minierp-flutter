# Quotation, sales-order, POS and reservation extension

Finalized by the lead from complete retained execution after worker handoff interruption. Invocation: `node accounting-audit/tests/sales-channel-extension.cjs`. Authoritative final run `evidence/sales-channel-run-AFjr5O`:692 assertions,685 pass,7 mismatches across4 defects,9 scenarios. Guard metadata records NODE_ENV=test and the single fresh fixture DB path. No production writes or app-source edits occurred.

| Scenario | Financial/control result | Status |
|---|---|---|
| Quotation→confirmed SO→invoice→cancel | Quotation/conversion nonposting; invoice recognition/stock/COGS correct; ordinary cancellation neutral | PASS economic path; FAIL repeated-cancel status F-070 |
| Direct SO Confirmed→Delivered→paid cancellation guard | Financial recognition/fulfillment checked; paid cancellation409 unchanged; payment reversal then cancellation neutral | PASS bounded scenario |
| POS cash walk-in/replay/partial return | Four units17.35, cash100, sale69.40/change30.60; same key replays without economic mutation, changed tender409; partial return checked | PASS |
| POS named credit/partial return | Five units17.35, payments[] creates credit obligation; replay and partial return reconcile | PASS; response display-name parity not certified |
| POS split Cash/Bank/AR | Three units17.35=52.05; Cash20+Bank15 leaves AR17.05 | PASS |
| POS explicit-zero tender | Walk-in cash_received0 must not generate receipt or release stock | FAIL Critical F-073:201, cash/payment+17.35, inventory−9.25, AR0 |
| Reservation replay with line id | One3-unit entitlement should reserve3 once and fully release | FAIL F-071: one row3, location reserved6; after release phantom3 remains |
| Single line reservation control | Create once/release restores available10; repeated release400 unchanged | PASS |
| Reservation without optional line id | Accepted2-unit reservation should release by its id | FAIL F-072:400 and ACTIVE/reserved2 remain |

Evidence includes ordered api-events.json, before/after economic hashes, SQL snapshots, individual/reference journal groups, A–J/extensions and signed receivables. Financial checks can pass when POS invents a cash event because all internal representations copy the same false premise; real tender is the independent oracle.

Independent final proof script opens only retained DBs read-only: `node accounting-audit/tests/final-extension-verifier.cjs`, output `evidence/final-extension-verification.json`. It checks actual cash/inventory deltas, reservation rows/location quantities, positive release control and the repeated-cancel unchanged hashes.

Superseded runs: uverx6 had an audit-only ordering query error; svc2jE used a short POS key and lacked a location fixture;5iZOGC lacks the final single-reservation positive control. These setup limitations are not findings. Final AFjr5O has no blocked scenario.

Feature-enabled reservations were explicitly fixture-enabled; no automatic SO→reservation coupling is claimed. No live Flutter channel action, mobile client, every discount/tax permutation, complete order editing or multi-process reservation race was verified. Four findings have their own folders F-070–073; the low-severity status issue is not described as financial corruption.
