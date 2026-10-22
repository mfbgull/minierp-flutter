# Fallow remediation ledger — plan `fallow-remediation-2026-10-21`

Generated 2026-10-22T03:48:19.469Z. Input of record: `audit/fallow-tools/fallow-before-20261021.json` (Fallow 3.34.1);
final scan: `/tmp/fallow-final.json` (Fallow 3.34.1); row inventory: `audit/fallow-remediation-2026-10-21.inventory.json`.

Post-commit review addendum (2026-10-22T05:04:03Z): D.1b, D.2 and the full-suite result in E were added after reconciling the final scan against the original inventory. The scan used for these tables is the evidence copy `.omo/evidence/task-6-fallow.json` (same content as `/tmp/fallow-final.json`).

## Totals

| Section | Original | Resolved | Retained with reason | Still reported (measured) | Open |
|---|---|---|---|---|---|
| Dead code | 63 | 2 (report rows) | 33 live + 28 vocabulary | — | 0 |
| Clone groups | 39 | 35 | 4 | — | 0 |
| Health — structural | 75 | 75 | — | 0 | 0 |
| Health — CRAP-only | 163 | — | — | see C.2 | 0 |
| **Total** | **340** | | | | **0** |

Every one of the 340 original entries has a row below with owner, action, evidence and
reason. Nothing is deferred, suppressed or hidden behind a changed threshold: the
D14 policy (`.fallowrc.json` `audit.gate: "new-only"`) and all baselines are untouched.

The 340 original entries have 0 open items. The inventory JSON is the pre-remediation
snapshot; its `pending-*` statuses are historical and are superseded by the final
dispositions in this ledger.

Post-remediation scan additions (not part of the original 340) are recorded in D:

| Post-remediation addition | Count | Status |
|---|---|---|
| New named symbols | 6 | Still reported (CRAP 30–90); recorded in D.1b |
| Anonymous arrow findings | 2 | Newly reported; recorded in D.1b |
| Pre-existing functions newly reported | 72 | Recorded in D.2; not introduced by extraction |

## A. Dead code (63 entries)

### A.1 Removed — 1 symbol, reported as 2 rows

The captured report lists the same unused method twice (once under the class
name, once under fallow's `default` pseudo-class). Both rows are counted and
resolve to one deletion.

| Report row | Path | Symbol as reported | Owner | Action | Evidence |
|---|---|---|---|---|---|
| `dc1:unused-class-member:6c345197036f4a48` | `server/src/services/accountingService.ts:1543` | `AccountingService.openPeriod` | services | **REMOVED** — method deleted | No qualified external caller in `audit/fallow-tools/class-member-verdicts.json` (only a same-named local SQL variable); source no longer declares it; `npm run typecheck` passes; `unused_class_members` 35 → 33 |
| `dc1:unused-class-member:5cd9470ff75d62d5` | `server/src/services/accountingService.ts:1543` | `default.openPeriod` | services | **REMOVED** — method deleted | No qualified external caller in `audit/fallow-tools/class-member-verdicts.json` (only a same-named local SQL variable); source no longer declares it; `npm run typecheck` passes; `unused_class_members` 35 → 33 |

### A.2 Retained — 33 class members (live symbols)

Each row was verified by resolving the reported `default.<member>` pseudo-symbol to its
real owning class and finding qualified external call sites.

| Report row | Path | Symbol | Owner | Action | Evidence (call sites) |
|---|---|---|---|---|---|
| `dc1:unused-class-member:aac174de68b660ee` | `server/src/models/EmployeeLoan.ts:100` | `default.getById` | models | RETAINED — reachable | `controllers/employeeController.ts:332`<br>`controllers/employeeController.ts:814`<br>… +6 more |
| `dc1:unused-class-member:56e2f8e84505f065` | `server/src/models/EmployeeLoan.ts:104` | `default.getByEmployee` | models | RETAINED — reachable | `controllers/employeeController.ts:730` |
| `dc1:unused-class-member:b2ea83e8bdb68b84` | `server/src/models/EmployeeLoan.ts:110` | `default.getRepayments` | models | RETAINED — reachable | `controllers/employeeController.ts:835` |
| `dc1:unused-class-member:ce83b2dc14c9493b` | `server/src/models/EmployeeLoan.ts:116` | `default.getRepaymentById` | models | RETAINED — reachable | `controllers/employeeController.ts:1080` |
| `dc1:unused-class-member:aaba87fdc9e6c808` | `server/src/models/EmployeeLoan.ts:120` | `default.getSummary` | models | RETAINED — reachable | `controllers/employeeController.ts:731` |
| `dc1:unused-class-member:254d4e998536dc50` | `server/src/models/EmployeeLoan.ts:133` | `default.hasRepayments` | models | RETAINED — reachable | `controllers/employeeController.ts:739`<br>`controllers/employeeController.ts:1047` |
| `dc1:unused-class-member:ab2e599f61e80df8` | `server/src/models/EmployeeLoan.ts:140` | `default.updateJournalEntry` | models | RETAINED — reachable | `controllers/employeeController.ts:811`<br>`controllers/employeeController.ts:1010` |
| `dc1:unused-class-member:33d8d3d0fd547183` | `server/src/models/EmployeeLoan.ts:192` | `default.updateRepaymentJournal` | models | RETAINED — reachable | `controllers/employeeController.ts:351`<br>`controllers/employeeController.ts:948` |
| `dc1:unused-class-member:e7810d001349f1d0` | `server/src/models/EmployeeLoan.ts:199` | `default.writeOff` | models | RETAINED — reachable | `controllers/employeeController.ts:989` |
| `dc1:unused-class-member:43ac4825dfd4ad20` | `server/src/models/EmployeeLoan.ts:251` | `default.getGlobalActiveLoans` | models | RETAINED — reachable | `controllers/dashboardController.ts:351` |
| `dc1:unused-class-member:0f55a3bc2e9be2c1` | `server/src/models/EmployeeLoan.ts:269` | `default.getGlobalLoanSummary` | models | RETAINED — reachable | `controllers/dashboardController.ts:352` |
| `dc1:unused-class-member:4891044cfddc4a1e` | `server/src/services/accountingService.ts:172` | `AccountingService.getAllAccountBalances` | services | RETAINED — reachable | `__tests__/expenseStatusConsistency.test.ts:179`<br>`controllers/accountingController.ts:104`<br>… +4 more |
| `dc1:unused-class-member:f95a612b0df00b17` | `server/src/services/accountingService.ts:186` | `AccountingService.getPeriodMovement` | services | RETAINED — reachable | `models/Reports.ts:422`<br>`models/Reports.ts:425`<br>… +3 more |
| `dc1:unused-class-member:31b2a152ad9203c6` | `server/src/services/accountingService.ts:519` | `AccountingService.postInvoiceEntry` | services | RETAINED — reachable | `server/scripts/verify-reversal-rules.ts:148`<br>`controllers/invoiceController.ts:663`<br>… +1 more |
| `dc1:unused-class-member:fe62a91a8e9f178b` | `server/src/services/accountingService.ts:579` | `AccountingService.postPaymentEntry` | services | RETAINED — reachable | `controllers/invoiceController.ts:596`<br>`models/Payment.ts:147`<br>… +1 more |
| `dc1:unused-class-member:5c9aca51e09f1d87` | `server/src/services/accountingService.ts:620` | `AccountingService.postCreditOffsetEntry` | services | RETAINED — reachable | `services/InvoiceCreationService.ts:240`<br>`services/PaymentRecordingService.ts:161` |
| `dc1:unused-class-member:25502cb0fe669547` | `server/src/services/accountingService.ts:667` | `AccountingService.postGoodsReceiptEntry` | services | RETAINED — reachable | `models/PurchaseOrder.ts:1101` |
| `dc1:unused-class-member:8e31524e63884f0e` | `server/src/services/accountingService.ts:711` | `AccountingService.postPurchaseEntry` | services | RETAINED — reachable | `models/Purchase.ts:328` |
| `dc1:unused-class-member:a148fa57f6f67fdb` | `server/src/services/accountingService.ts:758` | `AccountingService.postSupplierPaymentEntry` | services | RETAINED — reachable | `models/Payment.ts:160`<br>`services/SupplierPaymentService.ts:125` |
| `dc1:unused-class-member:190f5cc835a03bc5` | `server/src/services/accountingService.ts:798` | `AccountingService.postExpenseEntry` | services | RETAINED — reachable | `models/Expense.ts:229` |
| `dc1:unused-class-member:a90eea2da74a8b4c` | `server/src/services/accountingService.ts:905` | `AccountingService.postOwnerCapitalEntry` | services | RETAINED — reachable | `models/OwnerCapital.ts:72`<br>`models/OwnerCapital.ts:188` |
| `dc1:unused-class-member:9342747106485a16` | `server/src/services/accountingService.ts:942` | `AccountingService.postOwnerWithdrawalCashEntry` | services | RETAINED — reachable | `models/OwnerWithdrawal.ts:235`<br>`models/OwnerWithdrawal.ts:476` |
| `dc1:unused-class-member:188e8ab5f8d0e887` | `server/src/services/accountingService.ts:983` | `AccountingService.postOwnerWithdrawalGoodsEntry` | services | RETAINED — reachable | `models/OwnerWithdrawal.ts:287`<br>`models/OwnerWithdrawal.ts:556` |
| `dc1:unused-class-member:f84af7911a6efa12` | `server/src/services/accountingService.ts:1085` | `AccountingService.assertNoActivePosting` | services | RETAINED — reachable | `__tests__/ownerEquity.test.ts:185`<br>`models/OwnerCapital.ts:70`<br>… +2 more |
| `dc1:unused-class-member:7e58bcafc45b7bf5` | `server/src/services/accountingService.ts:1107` | `AccountingService.postCOGSEntry` | services | RETAINED — reachable | `server/scripts/verify-reversal-rules.ts:152`<br>`controllers/invoiceController.ts:673`<br>… +1 more |
| `dc1:unused-class-member:d4b52e158f032044` | `server/src/services/accountingService.ts:1153` | `default.postCOGSReversalEntry` | services | RETAINED — reachable | `services/invoiceReturnService.ts:429` |
| `dc1:unused-class-member:d2a465aa0cb0de99` | `server/src/services/accountingService.ts:1211` | `default.postInvoiceReturnEntry` | services | RETAINED — reachable | `__tests__/glReturnTaxBalance.test.ts:42`<br>`services/invoiceReturnService.ts:411` |
| `dc1:unused-class-member:c3f5ea81ff4a7c3e` | `server/src/services/accountingService.ts:1285` | `default.postReturnFeeEntry` | services | RETAINED — reachable | `__tests__/glReturnTaxBalance.test.ts:52`<br>`services/invoiceReturnService.ts:419` |
| `dc1:unused-class-member:2977847bcc6bdaa8` | `server/src/services/accountingService.ts:1327` | `AccountingService.postPurchaseReturnEntry` | services | RETAINED — reachable | `models/PurchaseReturn.ts:29`<br>`models/PurchaseReturn.ts:713` |
| `dc1:unused-class-member:e94616dbd9ed3ddf` | `server/src/services/accountingService.ts:1380` | `AccountingService.postRefundEntry` | services | RETAINED — reachable | `models/Payment.ts:134`<br>`services/PaymentRecordingService.ts:180` |
| `dc1:unused-class-member:55f9a3fdc0fc8759` | `server/src/services/accountingService.ts:1469` | `AccountingService.restoreJournalLinesByReference` | services | RETAINED — reachable | `server/scripts/rollback-customer15-correction.ts:7`<br>`controllers/invoiceController.ts:930`<br>… +1 more |
| `dc1:unused-class-member:ec57c122e3f4e1d5` | `server/src/services/accountingService.ts:1511` | `AccountingService.voidOwnInvoiceReturnLines` | services | RETAINED — reachable | `models/Invoice.ts:1003` |
| `dc1:unused-class-member:849deb27e1c72d7a` | `server/src/services/accountingService.ts:1691` | `default.postLoanWriteOff` | services | RETAINED — reachable | `controllers/employeeController.ts:995` |

### A.3 Retained — 28 enum members (persisted vocabulary)

| Report row | Path | Member | Owner | Action | Reason |
|---|---|---|---|---|---|
| `dc1:unused-enum-member:6363d36b85c18d91` | `server/src/services/activityLogger.ts:32` | `ActionType.PO_CREATE` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:7c5643ffac7e740a` | `server/src/services/activityLogger.ts:33` | `ActionType.PO_UPDATE` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:f99d5cb309845a4a` | `server/src/services/activityLogger.ts:34` | `ActionType.PO_APPROVE` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:4a8052bf2d57b58f` | `server/src/services/activityLogger.ts:35` | `ActionType.PO_CANCEL` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:f1b2ab8ec008701c` | `server/src/services/activityLogger.ts:36` | `ActionType.PO_DELETE` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:c959c29ad118bb11` | `server/src/services/activityLogger.ts:37` | `ActionType.GRN_CREATE` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:e24c332ef7d5a18a` | `server/src/services/activityLogger.ts:38` | `ActionType.GRN_UPDATE` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:d35411b17a177fa6` | `server/src/services/activityLogger.ts:51` | `ActionType.SO_CREATE` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:daeed0621c164511` | `server/src/services/activityLogger.ts:52` | `ActionType.SO_UPDATE` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:8ec3ec0cbcc34710` | `server/src/services/activityLogger.ts:53` | `ActionType.SO_CONFIRM` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:1db1a1bd09455ee3` | `server/src/services/activityLogger.ts:54` | `ActionType.SO_DELIVER` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:9ba2db28902533dd` | `server/src/services/activityLogger.ts:55` | `ActionType.SO_INVOICE` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:566d52f6f1a7eb4c` | `server/src/services/activityLogger.ts:56` | `ActionType.SO_CANCEL` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:8cf24b48093db84f` | `server/src/services/activityLogger.ts:57` | `ActionType.SO_DELETE` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:f0642a170c3afcad` | `server/src/services/activityLogger.ts:62` | `ActionType.INVOICE_POST` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:a84200b57843ba75` | `server/src/services/activityLogger.ts:65` | `ActionType.INVOICE_RETURN` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:2b7091f3b64d1c0c` | `server/src/services/activityLogger.ts:82` | `ActionType.WO_START` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:4385d3bc2adf687b` | `server/src/services/activityLogger.ts:83` | `ActionType.WO_COMPLETE` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:e3e7edd7eace1f38` | `server/src/services/activityLogger.ts:84` | `ActionType.WO_CANCEL` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:7f563ec40cf1ce4f` | `server/src/services/activityLogger.ts:86` | `ActionType.MATERIAL_CONSUME` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:c06f6dab93b9967f` | `server/src/services/activityLogger.ts:106` | `ActionType.DATA_IMPORT` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:6c2bb391a6b65712` | `server/src/services/activityLogger.ts:107` | `ActionType.DATA_EXPORT` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:375ae81bfda4336f` | `server/src/services/activityLogger.ts:111` | `ActionType.POS_SALE` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:09cbce62e3b4675c` | `server/src/services/activityLogger.ts:112` | `ActionType.POS_RETURN` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:202bdadc1abcbbfb` | `server/src/services/activityLogger.ts:115` | `ActionType.REPORT_GENERATE` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:bf5013d629bf16b0` | `server/src/services/activityLogger.ts:116` | `ActionType.REPORT_EXPORT` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:a60d61a20c294c20` | `server/src/services/activityLogger.ts:121` | `LogLevel.DEBUG` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |
| `dc1:unused-enum-member:2bab67a6cc141fe3` | `server/src/services/activityLogger.ts:124` | `LogLevel.ERROR` | services | RETAINED — vocabulary | Persisted vocabulary: `activity_logs.action_type` rows written before this cleanup still name this member, so deleting it would erase the meaning of historical rows |

## B. Duplicate groups (39 groups)

### B.1 Resolved — 35 groups

| Fingerprint | Owner | Former instances | Resolution |
|---|---|---|---|
| `dup:31de3227` | controllers | 5× (`controllers/employeeController.ts:65`<br>`controllers/employeeController.ts:482`<br>`controllers/employeeController.ts:611`<br>`controllers/employeeController.ts:630`<br>`controllers/employeeController.ts:716`) | Repeated blocks inside one module collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:82a87f0f` | controllers | 6× (`controllers/inventoryController.ts:15`<br>`controllers/inventoryController.ts:774`<br>`controllers/inventoryController.ts:809`<br>`controllers/purchaseReturnController.ts:8`<br>`controllers/salesController.ts:73`<br>`controllers/salesController.ts:258`) | Cross-module clones collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:36e0053a` | controllers | 5× (`controllers/inventoryController.ts:40`<br>`controllers/inventoryController.ts:561`<br>`controllers/inventoryController.ts:788`<br>`controllers/inventoryController.ts:821`<br>`controllers/supplierRefundController.ts:17`) | Cross-module clones collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:a08ba3bb` | controllers | 4× (`controllers/inventoryController.ts:809`<br>`controllers/invoiceController.ts:125`<br>`controllers/salesController.ts:73`<br>`controllers/salesController.ts:258`) | Cross-module clones collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:d0c6ebb5` | models | 3× (`models/Production.ts:171`<br>`models/Purchase.ts:123`<br>`models/PurchaseOrder.ts:218`) | Cross-module clones collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:fd6c6b7f` | models | 5× (`models/BOM.ts:85`<br>`models/OwnerWithdrawal.ts:128`<br>`models/Production.ts:174`<br>`models/Purchase.ts:126`<br>`models/PurchaseOrder.ts:226`) | Cross-module clones collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:a594d0a8` | controllers | 5× (`controllers/customersController.ts:78`<br>`controllers/employeeController.ts:107`<br>`controllers/employeeController.ts:202`<br>`controllers/employeeController.ts:209`<br>`controllers/suppliersController.ts:286`) | Cross-module clones collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:559d53da` | controllers | 4× (`controllers/invoiceController.ts:151`<br>`controllers/invoiceController.ts:1188`<br>`controllers/salesController.ts:95`<br>`controllers/salesController.ts:281`) | Cross-module clones collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:59f71812` | controllers | 3× (`controllers/ownerPersonalLoansController.ts:713`<br>`controllers/ownerPersonalLoansController.ts:746`<br>`controllers/ownerPersonalLoansController.ts:769`) | Repeated blocks inside one module collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:d6f9d6c0` | controllers | 3× (`controllers/ownerEquityController.ts:104`<br>`controllers/ownerEquityController.ts:326`<br>`controllers/purchaseOrderController.ts:409`) | Cross-module clones collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:b23a802c` | controllers | 3× (`controllers/employeeController.ts:482`<br>`controllers/employeeController.ts:611`<br>`controllers/employeeController.ts:630`) | Repeated blocks inside one module collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:66fc37bd` | remaining | 3× (`server/scripts/backfill-ledger-dates.js:23`<br>`server/scripts/dedupe-po.js:26`<br>`server/scripts/recompute-item-amounts.js:51`) | Cross-module clones collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:c4d0924d` | controllers | 4× (`controllers/productionController.ts:140`<br>`controllers/purchaseController.ts:213`<br>`controllers/purchaseOrderController.ts:112`<br>`controllers/purchaseReturnController.ts:34`) | Cross-module clones collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:2bcde3d5` | models | 4× (`models/BOM.ts:85`<br>`models/Production.ts:174`<br>`models/Purchase.ts:126`<br>`models/PurchaseOrder.ts:226`) | Cross-module clones collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:47019eb7` | controllers | 3× (`controllers/inventoryController.ts:809`<br>`controllers/salesController.ts:73`<br>`controllers/salesController.ts:258`) | Cross-module clones collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:d87f4d72` | models | 4× (`models/Production.ts:174`<br>`models/Purchase.ts:126`<br>`models/PurchaseOrder.ts:226`<br>`utils/sequence.ts:27`) | Cross-module clones collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:2e389da0` | controllers | 3× (`controllers/inventoryController.ts:38`<br>`controllers/inventoryController.ts:786`<br>`controllers/inventoryController.ts:819`) | Repeated blocks inside one module collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:a3471acf` | models | 3× (`models/Expense.ts:53`<br>`models/OwnerCapital.ts:44`<br>`models/OwnerWithdrawal.ts:76`) | Cross-module clones collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:74d8a899` | models | 3× (`models/Invoice.ts:500`<br>`models/InvoiceReturn.ts:89`<br>`models/InvoiceReturn.ts:114`) | Cross-module clones collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:162f33b3` | controllers | 3× (`controllers/suppliersController.ts:54`<br>`controllers/suppliersController.ts:270`<br>`controllers/suppliersController.ts:341`) | Repeated blocks inside one module collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:5b440746` | controllers | 3× (`controllers/invoiceController.ts:151`<br>`controllers/salesController.ts:95`<br>`controllers/salesController.ts:281`) | Cross-module clones collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:a4eb6554` | controllers | 3× (`controllers/customersController.ts:109`<br>`controllers/customersController.ts:133`<br>`controllers/customersController.ts:166`) | Repeated blocks inside one module collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:b504882c` | controllers | 3× (`controllers/employeeController.ts:202`<br>`controllers/employeeController.ts:209`<br>`controllers/suppliersController.ts:286`) | Cross-module clones collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:0a1ca975` | controllers | 3× (`controllers/reportsController.ts:122`<br>`controllers/reportsController.ts:137`<br>`controllers/reportsController.ts:145`) | Repeated blocks inside one module collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:2383cf9f` | remaining | 3× (`server/scripts/backfill-ledger-dates.js:33`<br>`server/scripts/dedupe-po.js:36`<br>`server/scripts/recompute-item-amounts.js:61`) | Cross-module clones collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:6d5a9349` | controllers | 3× (`controllers/employeeController.ts:357`<br>`controllers/employeeController.ts:525`<br>`controllers/employeeController.ts:754`) | Repeated blocks inside one module collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:f6b635c5` | controllers | 3× (`controllers/ownerEquityController.ts:88`<br>`controllers/ownerPersonalLoansController.ts:177`<br>`controllers/ownerPersonalLoansController.ts:410`) | Cross-module clones collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:305f54ab` | models | 3× (`models/StockMovement.ts:1250`<br>`models/StockMovement.ts:1387`<br>`models/StockMovement.ts:1502`) | Repeated blocks inside one module collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:58949ae7` | remaining | 3× (`middleware/rateLimiter.ts:13`<br>`middleware/rateLimiter.ts:35`<br>`middleware/rateLimiter.ts:102`) | Repeated blocks inside one module collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:827d201f` | services | 3× (`services/accountingService.ts:775`<br>`services/accountingService.ts:919`<br>`services/accountingService.ts:956`) | Repeated blocks inside one module collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:1c02a814` | controllers | 3× (`controllers/invoiceController.ts:843`<br>`controllers/invoiceReturnController.ts:53`<br>`controllers/invoiceReturnController.ts:72`) | Cross-module clones collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:3b83cf27` | controllers | 3× (`controllers/accountingController.ts:98`<br>`controllers/accountingController.ts:133`<br>`controllers/accountingController.ts:154`) | Repeated blocks inside one module collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:1b29f147` | controllers | 3× (`controllers/ownerPersonalLoansController.ts:703`<br>`controllers/ownerPersonalLoansController.ts:759`<br>`controllers/ownerPersonalLoansController.ts:786`) | Repeated blocks inside one module collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:9541b61c` | controllers | 3× (`controllers/ownerPersonalLoansController.ts:666`<br>`controllers/ownerPersonalLoansController.ts:716`<br>`controllers/ownerPersonalLoansController.ts:772`) | Repeated blocks inside one module collapsed into one shared operation; the fingerprint is absent from the final scan |
| `dup:e4702e5d` | controllers | 3× (`controllers/customersController.ts:13`<br>`controllers/paymentsController.ts:44`<br>`controllers/suppliersController.ts:14`) | Cross-module clones collapsed into one shared operation; the fingerprint is absent from the final scan |

### B.2 Retained — 4 groups (concrete differences)

| Fingerprint | Owner | Instances (final scan) | Why it stays |
|---|---|---|---|
| `dup:4d3320a0` | models | 6× (`models/Reports.ts:965`<br>`models/Reports.ts:978`<br>`models/Reports.ts:1021`<br>`models/Reports.ts:1034`<br>`models/Reports.ts:1046`<br>`models/Reports.ts:1083`) | Six cash-flow row queries in `models/Reports.ts`, one per source table (customer payment, supplier payment, salary, capital, withdrawal, refund). Each selects different columns, joins and predicates; only the aliased output shape looks alike. Merging them would need a table-driven SQL builder that hides which columns each flow reads. |
| `dup:e2a1deae` | models | 3× (`models/PhysicalCount.ts:225`<br>`models/StockMovement.ts:668`<br>`models/StockMovement.ts:956`) | Sort-column defaulting in `models/PhysicalCount.ts` and `models/StockMovement.ts`. Each site uses a different allow-list map (`COUNT_SORT_COLUMN_MAP`, `SORT_COLUMN_MAP`, `BALANCE_SORT_COLUMN_MAP`) and a different SQL table alias (`pc.`, `sm.`, `i.`) as its fallback. A shared helper would have to take the map and the fallback as parameters, moving each query's sort policy out of the query it belongs to. |
| `dup:c79c25b2` | controllers | 3× (`controllers/reportsController.ts:62`<br>`controllers/reportsController.ts:98`<br>`controllers/reportsController.ts:107`) | Three report handlers in `controllers/reportsController.ts` share a date prologue but differ in their missing-date defaults — the plan explicitly retains group 27 for that reason. Unifying the defaults would change which period each report covers when the client omits a date. |
| `dup:b49eb11a` | models | 3× (`models/BOM.ts:199`<br>`models/Production.ts:645`<br>`models/PurchaseReturn.ts:488`) | Paginated header queries in `models/BOM.ts`, `models/Production.ts` and `models/PurchaseReturn.ts`. The shared part is only the `ORDER BY <sortColumn> LIMIT/OFFSET` tail; the SELECT bodies and sort allow-lists differ, and each model owns its own SQL. |

## C. Health findings (238 entries)

### C.1 Structural complexity (cyclomatic > 20 or cognitive > 15) — 75 entries, 0 remaining

| Report row | Path | Symbol | Owner | Before (cyc/cog) | Final state |
|---|---|---|---|---|---|
| `health:server/src/models/PhysicalCount.ts:transaction:510` | `server/src/models/PhysicalCount.ts` | `transaction` | models | 30/67 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/services/invoiceReturnService.ts:txn:301` | `server/src/services/invoiceReturnService.ts` | `txn` | services | 30/38 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/__tests__/accountingInvariants.test.ts:it("holds after invoice → payment → return →..."):153` | `server/src/__tests__/accountingInvariants.test.ts` | `it("holds after invoice → payment → return →...")` | remaining | 28/24 | Resolved — same symbol now measures 10/5 |
| `health:server/src/controllers/preferencesController.ts:updatePreferences:49` | `server/src/controllers/preferencesController.ts` | `updatePreferences` | controllers | 27/33 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/controllers/productionController.ts:recordProduction:10` | `server/src/controllers/productionController.ts` | `recordProduction` | controllers | 27/35 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/models/Expense.ts:<arrow>:179` | `server/src/models/Expense.ts` | `<arrow>` | models | 27/27 | Resolved — not present under this name; the logic moved into extracted operations |
| `health:server/src/controllers/mobileInvoiceController.ts:processReturn:249` | `server/src/controllers/mobileInvoiceController.ts` | `processReturn` | controllers | 26/23 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/controllers/invoiceController.ts:returnInvoiceItems:1081` | `server/src/controllers/invoiceController.ts` | `returnInvoiceItems` | controllers | 25/23 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/models/SalesOrder.ts:transaction:115` | `server/src/models/SalesOrder.ts` | `transaction` | models | 25/31 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/controllers/customReportsController.ts:validateReportConfig:55` | `server/src/controllers/customReportsController.ts` | `validateReportConfig` | controllers | 24/39 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/controllers/employeeController.ts:trx:890` | `server/src/controllers/employeeController.ts` | `trx` | controllers | 24/22 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/controllers/paymentsController.ts:getPaymentReceipt:418` | `server/src/controllers/paymentsController.ts` | `getPaymentReceipt` | controllers | 24/27 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/models/Production.ts:transaction:240` | `server/src/models/Production.ts` | `transaction` | models | 24/34 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/models/Quotation.ts:transaction:117` | `server/src/models/Quotation.ts` | `transaction` | models | 24/28 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/services/cashService.ts:getCashAccountTransactions:529` | `server/src/services/cashService.ts` | `getCashAccountTransactions` | services | 24/25 | Resolved — same symbol now measures 14/15 |
| `health:server/src/controllers/mobileInvoiceController.ts:submitInvoice:149` | `server/src/controllers/mobileInvoiceController.ts` | `submitInvoice` | controllers | 23/30 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/models/Dashboard.ts:getKPI:448` | `server/src/models/Dashboard.ts` | `getKPI` | models | 23/6 | Resolved — same symbol now measures 19/7 |
| `health:server/src/controllers/posController.ts:createPOSSale:210` | `server/src/controllers/posController.ts` | `createPOSSale` | controllers | 22/24 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/services/cashService.ts:collectFlows:102` | `server/src/services/cashService.ts` | `collectFlows` | services | 22/21 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/scripts/verify-reversal-rules.ts:main:68` | `server/scripts/verify-reversal-rules.ts` | `main` | remaining | 21/12 | Resolved — same symbol now measures 19/10 |
| `health:server/src/controllers/userController.ts:updateUser:110` | `server/src/controllers/userController.ts` | `updateUser` | controllers | 21/21 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/models/PurchaseReturn.ts:transaction:759` | `server/src/models/PurchaseReturn.ts` | `transaction` | models | 21/45 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/services/InvoiceCreationService.ts:transaction:155` | `server/src/services/InvoiceCreationService.ts` | `transaction` | services | 21/25 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/services/accountingService.ts:postEntry:243` | `server/src/services/accountingService.ts` | `postEntry` | services | 21/25 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/services/paymentValidation.ts:validateSupplierPayment:110` | `server/src/services/paymentValidation.ts` | `validateSupplierPayment` | services | 21/32 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/controllers/employeeController.ts:paySalary:354` | `server/src/controllers/employeeController.ts` | `paySalary` | controllers | 20/18 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/controllers/invoiceController.ts:transaction:504` | `server/src/controllers/invoiceController.ts` | `transaction` | controllers | 20/19 | Resolved — same symbol now measures 12/13 |
| `health:server/src/controllers/ownerPersonalLoansController.ts:updateBorrower:662` | `server/src/controllers/ownerPersonalLoansController.ts` | `updateBorrower` | controllers | 20/19 | Resolved — same symbol now measures 12/11 |
| `health:server/src/controllers/purchaseController.ts:recordPurchase:71` | `server/src/controllers/purchaseController.ts` | `recordPurchase` | controllers | 20/26 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/models/Payment.ts:update:562` | `server/src/models/Payment.ts` | `update` | models | 20/22 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/models/StockMovement.ts:transaction:472` | `server/src/models/StockMovement.ts` | `transaction` | models | 20/21 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/models/Invoice.ts:reverseStockForItems:569` | `server/src/models/Invoice.ts` | `reverseStockForItems` | models | 19/44 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/config/database.ts:<arrow>:1118` | `server/src/config/database.ts` | `<arrow>` | remaining | 18/18 | Resolved — same symbol now measures 14/14 |
| `health:server/src/controllers/inventoryController.ts:runWriteOff:1020` | `server/src/controllers/inventoryController.ts` | `runWriteOff` | controllers | 18/19 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/models/Invoice.ts:buildInvoiceInsertParams:206` | `server/src/models/Invoice.ts` | `buildInvoiceInsertParams` | models | 18/18 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/models/Quotation.ts:transaction:400` | `server/src/models/Quotation.ts` | `transaction` | models | 18/20 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/models/StockMovement.ts:run:1724` | `server/src/models/StockMovement.ts` | `run` | models | 18/30 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/__tests__/purchaseVoid.test.ts:seedPurchase:33` | `server/src/__tests__/purchaseVoid.test.ts` | `seedPurchase` | remaining | 17/16 | Resolved — same symbol now measures 10/9 |
| `health:server/src/controllers/expenseController.ts:updateExpense:283` | `server/src/controllers/expenseController.ts` | `updateExpense` | controllers | 17/17 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/controllers/invoiceController.ts:updateInvoice:450` | `server/src/controllers/invoiceController.ts` | `updateInvoice` | controllers | 17/24 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/models/Item.ts:create:190` | `server/src/models/Item.ts` | `create` | models | 17/17 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/models/OwnerWithdrawal.ts:update:431` | `server/src/models/OwnerWithdrawal.ts` | `update` | models | 17/19 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/services/InvoiceCreationService.ts:create:111` | `server/src/services/InvoiceCreationService.ts` | `create` | services | 17/20 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/services/reportQueryEngine.ts:executeReport:204` | `server/src/services/reportQueryEngine.ts` | `executeReport` | services | 17/19 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/controllers/ownerEquityController.ts:createWithdrawal:284` | `server/src/controllers/ownerEquityController.ts` | `createWithdrawal` | controllers | 16/18 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/controllers/ownerEquityController.ts:updateWithdrawal:448` | `server/src/controllers/ownerEquityController.ts` | `updateWithdrawal` | controllers | 16/18 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/controllers/purchaseOrderController.ts:createGoodsReceipt:363` | `server/src/controllers/purchaseOrderController.ts` | `createGoodsReceipt` | controllers | 16/17 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/models/Production.ts:transaction:736` | `server/src/models/Production.ts` | `transaction` | models | 16/21 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/models/PurchaseReturn.ts:drawFromSourceBatches:301` | `server/src/models/PurchaseReturn.ts` | `drawFromSourceBatches` | models | 16/26 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/models/StockMovement.ts:run:1592` | `server/src/models/StockMovement.ts` | `run` | models | 16/17 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/services/reportQueryEngine.ts:buildSelectClause:347` | `server/src/services/reportQueryEngine.ts` | `buildSelectClause` | services | 16/23 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/utils/purchaseReturnBackfill.ts:backfill:96` | `server/src/utils/purchaseReturnBackfill.ts` | `backfill` | remaining | 16/19 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/controllers/paymentsController.ts:allocatePaymentToInvoice:561` | `server/src/controllers/paymentsController.ts` | `allocatePaymentToInvoice` | controllers | 15/16 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/controllers/purchaseOrderController.ts:createPurchaseOrder:18` | `server/src/controllers/purchaseOrderController.ts` | `createPurchaseOrder` | controllers | 15/17 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/migrations/backfillGlUnification.ts:run:27` | `server/src/migrations/backfillGlUnification.ts` | `run` | remaining | 15/21 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/models/OwnerWithdrawal.ts:<arrow>:209` | `server/src/models/OwnerWithdrawal.ts` | `<arrow>` | models | 15/16 | Resolved — not present under this name; the logic moved into extracted operations |
| `health:server/src/models/PurchaseReturn.ts:transaction:564` | `server/src/models/PurchaseReturn.ts` | `transaction` | models | 15/25 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/services/forecastService.ts:readCachedForecasts:655` | `server/src/services/forecastService.ts` | `readCachedForecasts` | services | 15/21 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:scripts/openspec-archive-guard.js:main:109` | `scripts/openspec-archive-guard.js` | `main` | remaining | 14/17 | Resolved — same symbol now measures 12/15 |
| `health:server/src/controllers/invoiceController.ts:createInvoice:200` | `server/src/controllers/invoiceController.ts` | `createInvoice` | controllers | 14/19 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/migrations/backfillGlPreposting.ts:backfill23Payments:158` | `server/src/migrations/backfillGlPreposting.ts` | `backfill23Payments` | remaining | 14/29 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/models/PurchaseOrder.ts:transaction:917` | `server/src/models/PurchaseOrder.ts` | `transaction` | models | 14/20 | Resolved — same symbol now measures 6/5 |
| `health:server/src/models/SalesOrder.ts:transaction:411` | `server/src/models/SalesOrder.ts` | `transaction` | models | 14/16 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/services/SupplierPaymentService.ts:<arrow>:24` | `server/src/services/SupplierPaymentService.ts` | `<arrow>` | services | 14/18 | Resolved — not present under this name; the logic moved into extracted operations |
| `health:server/scripts/backup-db.js:run:43` | `server/scripts/backup-db.js` | `run` | remaining | 13/17 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/config/database.ts:run:1238` | `server/src/config/database.ts` | `run` | remaining | 13/25 | Resolved — same symbol now measures 7/9 |
| `health:server/src/services/reportQueryEngine.ts:assertComputedNamesAreSafe:166` | `server/src/services/reportQueryEngine.ts` | `assertComputedNamesAreSafe` | services | 13/18 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/services/reportQueryEngine.ts:resolveNeededJoins:464` | `server/src/services/reportQueryEngine.ts` | `resolveNeededJoins` | services | 13/18 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:scripts/openspec-archive-guard.js:parseArgv:58` | `scripts/openspec-archive-guard.js` | `parseArgv` | remaining | 12/18 | Resolved — same symbol now measures 8/9 |
| `health:server/scripts/repair-stock.ts:run:73` | `server/scripts/repair-stock.ts` | `run` | remaining | 12/22 | Resolved — same symbol now measures 6/8 |
| `health:server/src/models/Payment.ts:moveEditedPaymentLedgerDate:181` | `server/src/models/Payment.ts` | `moveEditedPaymentLedgerDate` | models | 12/22 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/models/PhysicalCount.ts:transaction:305` | `server/src/models/PhysicalCount.ts` | `transaction` | models | 12/24 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/models/PurchaseOrder.ts:run:687` | `server/src/models/PurchaseOrder.ts` | `run` | models | 12/16 | Resolved — still present, but no longer reported (now under both thresholds) |
| `health:server/src/scripts/reconcile-stock-cash.ts:flagDuplicatePurchases:134` | `server/src/scripts/reconcile-stock-cash.ts` | `flagDuplicatePurchases` | remaining | 11/24 | Resolved — same symbol now measures 6/9 |
| `health:server/src/routes/stockBatches.ts:router.get("/stock-batches"):50` | `server/src/routes/stockBatches.ts` | `router.get("/stock-batches")` | remaining | 10/22 | Resolved — not present under this name; the logic moved into extracted operations |

### C.2 CRAP-only findings — 163 entries

Recomputed after configuring test-only source maps (`server/tsconfig.test.json`,
`sourceMap: true`; production `server/tsconfig.json` untouched) and regenerating
coverage with the full server suite.

- **99 no longer reported** by the final scan (corrected mapping, refactored function, or coverage above the threshold).
- **64 still reported** with measured coverage; their measured score is recorded below rather than hidden.

| Report row | Path | Symbol | Owner | Original CRAP | Final state (measured) |
|---|---|---|---|---|---|
| `health:server/src/controllers/inventoryController.ts:createStockMovement:599` | `server/src/controllers/inventoryController.ts` | `createStockMovement` | controllers | 106.4 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/SupplierBill.ts:<arrow>:60` | `server/src/models/SupplierBill.ts` | `<arrow>` | models | 88 | No longer reported — the function moved into extracted operations |
| `health:server/src/controllers/employeeController.ts:repayLoan:847` | `server/src/controllers/employeeController.ts` | `repayLoan` | controllers | 79.4 | Still reported — CRAP 32.2 (cyc 17), coverage istanbul, partial |
| `health:server/src/models/SalesOrder.ts:convertToInvoice:620` | `server/src/models/SalesOrder.ts` | `convertToInvoice` | models | 79.4 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/inventoryController.ts:correctPhysicalCount:952` | `server/src/controllers/inventoryController.ts` | `correctPhysicalCount` | controllers | 71.3 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/ExpensePayment.ts:<arrow>:36` | `server/src/models/ExpensePayment.ts` | `<arrow>` | models | 71.3 | No longer reported — the function moved into extracted operations |
| `health:server/src/models/Invoice.ts:getAll:351` | `server/src/models/Invoice.ts` | `getAll` | models | 71.3 | Still reported — CRAP 38.9 (cyc 16), coverage istanbul, partial |
| `health:server/src/services/accountingService.ts:postPurchaseEntry:711` | `server/src/services/accountingService.ts` | `postPurchaseEntry` | services | 71.3 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/scripts/dev/audit-trace.ts:main:1231` | `server/scripts/dev/audit-trace.ts` | `main` | remaining | 240 | Still reported — CRAP 240 (cyc 15), coverage estimated, none |
| `health:server/scripts/fixtures/unapplied-cash-ui.cjs:control.post("/command"):80` | `server/scripts/fixtures/unapplied-cash-ui.cjs` | `control.post("/command")` | remaining | 240 | Still reported — CRAP 240 (cyc 15), coverage estimated, none |
| `health:server/src/__tests__/glPostingMatrix.test.ts:it("SO conversion produces subledger row plu..."):255` | `server/src/__tests__/glPostingMatrix.test.ts` | `it("SO conversion produces subledger row plu...")` | remaining | 63.6 | Still reported — CRAP 63.6 (cyc 15), coverage estimated, partial |
| `health:server/src/__tests__/purchaseReturn.test.ts:seedPO:157` | `server/src/__tests__/purchaseReturn.test.ts` | `seedPO` | remaining | 63.6 | Still reported — CRAP 63.6 (cyc 15), coverage estimated, partial |
| `health:server/src/controllers/dashboardController.ts:getBoot:216` | `server/src/controllers/dashboardController.ts` | `getBoot` | controllers | 63.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/expenseController.ts:createExpense:25` | `server/src/controllers/expenseController.ts` | `createExpense` | controllers | 63.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/ownerEquityController.ts:validateItemLines:260` | `server/src/controllers/ownerEquityController.ts` | `validateItemLines` | controllers | 63.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/suppliersController.ts:deleteSupplier:189` | `server/src/controllers/suppliersController.ts` | `deleteSupplier` | controllers | 63.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/Expense.ts:update:153` | `server/src/models/Expense.ts` | `update` | models | 63.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/Item.ts:update:226` | `server/src/models/Item.ts` | `update` | models | 63.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/Purchase.ts:validateCreateDTO:139` | `server/src/models/Purchase.ts` | `validateCreateDTO` | models | 63.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/Purchase.ts:getAll:436` | `server/src/models/Purchase.ts` | `getAll` | models | 63.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/SalesOrder.ts:getAll:273` | `server/src/models/SalesOrder.ts` | `getAll` | models | 63.6 | Still reported — CRAP 35.1 (cyc 15), coverage istanbul, partial |
| `health:server/src/models/StockMovement.ts:consumeFromOldestBatches:1149` | `server/src/models/StockMovement.ts` | `consumeFromOldestBatches` | models | 63.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/services/accountingService.ts:postGoodsReceiptEntry:667` | `server/src/services/accountingService.ts` | `postGoodsReceiptEntry` | services | 63.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/services/accountingService.ts:postPurchaseReturnEntry:1327` | `server/src/services/accountingService.ts` | `postPurchaseReturnEntry` | services | 63.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/services/expressionValidator.ts:parseCastArguments:305` | `server/src/services/expressionValidator.ts` | `parseCastArguments` | services | 63.6 | Still reported — CRAP 240 (cyc 15), coverage istanbul, none |
| `health:server/src/services/searchService.ts:search:848` | `server/src/services/searchService.ts` | `search` | services | 63.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/utils/ledgerUtils.ts:derivePaymentStatus:198` | `server/src/utils/ledgerUtils.ts` | `derivePaymentStatus` | remaining | 63.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/__tests__/purchaseReturn.test.ts:seedPurchase:69` | `server/src/__tests__/purchaseReturn.test.ts` | `seedPurchase` | remaining | 56.3 | Still reported — CRAP 56.3 (cyc 14), coverage estimated, partial |
| `health:server/src/controllers/customReportsController.ts:createTemplate:417` | `server/src/controllers/customReportsController.ts` | `createTemplate` | controllers | 56.3 | Still reported — CRAP 210 (cyc 14), coverage istanbul, none |
| `health:server/src/controllers/paymentsController.ts:createSupplierPayment:244` | `server/src/controllers/paymentsController.ts` | `createSupplierPayment` | controllers | 56.3 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/middleware/auth.ts:authenticateToken:16` | `server/src/middleware/auth.ts` | `authenticateToken` | remaining | 56.3 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/Quotation.ts:getAll:272` | `server/src/models/Quotation.ts` | `getAll` | models | 56.3 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/Reports.ts:getCashMovements:943` | `server/src/models/Reports.ts` | `getCashMovements` | models | 56.3 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/StockMovement.ts:consumeLegacyStock:400` | `server/src/models/StockMovement.ts` | `consumeLegacyStock` | models | 56.3 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/services/activityLogger.ts:flush:282` | `server/src/services/activityLogger.ts` | `flush` | services | 56.3 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/accountingController.ts:openPeriod:232` | `server/src/controllers/accountingController.ts` | `openPeriod` | controllers | 49.5 | Still reported — CRAP 182 (cyc 13), coverage istanbul, none |
| `health:server/src/controllers/employeeController.ts:applySalaryLoanDeduction:314` | `server/src/controllers/employeeController.ts` | `applySalaryLoanDeduction` | controllers | 49.5 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/employeeController.ts:trx:557` | `server/src/controllers/employeeController.ts` | `trx` | controllers | 49.5 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/inventoryController.ts:deleteWarehouse:463` | `server/src/controllers/inventoryController.ts` | `deleteWarehouse` | controllers | 49.5 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/userController.ts:createUser:64` | `server/src/controllers/userController.ts` | `createUser` | controllers | 49.5 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/userController.ts:toggleUserStatus:214` | `server/src/controllers/userController.ts` | `toggleUserStatus` | controllers | 49.5 | Still reported — CRAP 63.1 (cyc 13), coverage istanbul, partial |
| `health:server/src/models/OwnerWithdrawal.ts:getAll:331` | `server/src/models/OwnerWithdrawal.ts` | `getAll` | models | 49.5 | Still reported — CRAP 182 (cyc 13), coverage istanbul, none |
| `health:server/src/models/Production.ts:getAll:570` | `server/src/models/Production.ts` | `getAll` | models | 49.5 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/PurchaseReturn.ts:getAll:431` | `server/src/models/PurchaseReturn.ts` | `getAll` | models | 49.5 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/StockMovement.ts:getAll:595` | `server/src/models/StockMovement.ts` | `getAll` | models | 49.5 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/SupplierPrepayment.ts:<arrow>:81` | `server/src/models/SupplierPrepayment.ts` | `<arrow>` | models | 49.5 | No longer reported — the function moved into extracted operations |
| `health:server/src/services/forecastService.ts:runModel:285` | `server/src/services/forecastService.ts` | `runModel` | services | 49.5 | Still reported — CRAP 49.5 (cyc 13), coverage istanbul, partial |
| `health:server/src/controllers/employeeController.ts:addEmployeeDocument:630` | `server/src/controllers/employeeController.ts` | `addEmployeeDocument` | controllers | 43.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/inventoryController.ts:planOpeningStock:122` | `server/src/controllers/inventoryController.ts` | `planOpeningStock` | controllers | 43.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/invoiceController.ts:transaction:880` | `server/src/controllers/invoiceController.ts` | `transaction` | controllers | 43.1 | Still reported — CRAP 156 (cyc 12), coverage istanbul, none |
| `health:server/src/controllers/ownerPersonalLoansController.ts:listLoans:85` | `server/src/controllers/ownerPersonalLoansController.ts` | `listLoans` | controllers | 43.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/ownerPersonalLoansController.ts:createLoan:170` | `server/src/controllers/ownerPersonalLoansController.ts` | `createLoan` | controllers | 43.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/ownerPersonalLoansController.ts:<arrow>:338` | `server/src/controllers/ownerPersonalLoansController.ts` | `<arrow>` | controllers | 43.1 | No longer reported — the function moved into extracted operations |
| `health:server/src/controllers/purchaseOrderController.ts:voidGoodsReceipt:331` | `server/src/controllers/purchaseOrderController.ts` | `voidGoodsReceipt` | controllers | 43.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/purchaseReturnController.ts:createPurchaseReturn:71` | `server/src/controllers/purchaseReturnController.ts` | `createPurchaseReturn` | controllers | 43.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/middleware/activityLog.ts:res.on("finish"):54` | `server/src/middleware/activityLog.ts` | `res.on("finish")` | remaining | 43.1 | No longer reported — the function moved into extracted operations |
| `health:server/src/models/ActivityLog.ts:find:112` | `server/src/models/ActivityLog.ts` | `find` | models | 43.1 | Still reported — CRAP 156 (cyc 12), coverage istanbul, none |
| `health:server/src/models/Invoice.ts:getReturnHistory:1226` | `server/src/models/Invoice.ts` | `getReturnHistory` | models | 43.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/Payment.ts:getUnifiedPayments:381` | `server/src/models/Payment.ts` | `getUnifiedPayments` | models | 43.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/Payment.ts:<arrow>:629` | `server/src/models/Payment.ts` | `<arrow>` | models | 43.1 | No longer reported — the function moved into extracted operations |
| `health:server/src/models/PurchaseOrder.ts:getAll:235` | `server/src/models/PurchaseOrder.ts` | `getAll` | models | 43.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/StockMovement.ts:postFinancialEntryForAdjustment:749` | `server/src/models/StockMovement.ts` | `postFinancialEntryForAdjustment` | models | 43.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/StockMovement.ts:run:1333` | `server/src/models/StockMovement.ts` | `run` | models | 43.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/SupplierRefund.ts:create:138` | `server/src/models/SupplierRefund.ts` | `create` | models | 43.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/services/InvoiceCreationService.ts:validateInput:97` | `server/src/services/InvoiceCreationService.ts` | `validateInput` | services | 43.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/services/reportQueryEngine.ts:buildFilterExpression:637` | `server/src/services/reportQueryEngine.ts` | `buildFilterExpression` | services | 43.1 | Still reported — CRAP 30 (cyc 12), coverage istanbul, partial |
| `health:server/scripts/dev/audit-trace.ts:runAllMigrations:76` | `server/scripts/dev/audit-trace.ts` | `runAllMigrations` | remaining | 132 | Still reported — CRAP 132 (cyc 11), coverage estimated, none |
| `health:server/src/__tests__/accountingInvariants.test.ts:it("voiding a stock transfer twice: second a..."):464` | `server/src/__tests__/accountingInvariants.test.ts` | `it("voiding a stock transfer twice: second a...")` | remaining | 37.1 | Still reported — CRAP 37.1 (cyc 11), coverage estimated, partial |
| `health:server/src/__tests__/auditRegression9.test.ts:it("splits materials + overhead between outp..."):467` | `server/src/__tests__/auditRegression9.test.ts` | `it("splits materials + overhead between outp...")` | remaining | 37.1 | Still reported — CRAP 37.1 (cyc 11), coverage estimated, partial |
| `health:server/src/__tests__/search.test.ts:createFixture:13` | `server/src/__tests__/search.test.ts` | `createFixture` | remaining | 37.1 | Still reported — CRAP 37.1 (cyc 11), coverage estimated, partial |
| `health:server/src/config/database.ts:runLedgered:162` | `server/src/config/database.ts` | `runLedgered` | remaining | 37.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/accountingController.ts:closePeriod:313` | `server/src/controllers/accountingController.ts` | `closePeriod` | controllers | 37.1 | Still reported — CRAP 132 (cyc 11), coverage istanbul, none |
| `health:server/src/controllers/bomController.ts:createBOM:69` | `server/src/controllers/bomController.ts` | `createBOM` | controllers | 132 | Still reported — CRAP 132 (cyc 11), coverage istanbul, none |
| `health:server/src/controllers/customReportsController.ts:updateReport:221` | `server/src/controllers/customReportsController.ts` | `updateReport` | controllers | 37.1 | Still reported — CRAP 132 (cyc 11), coverage istanbul, none |
| `health:server/src/controllers/employeeController.ts:createEmployee:81` | `server/src/controllers/employeeController.ts` | `createEmployee` | controllers | 37.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/employeeController.ts:deleteSalaryPayment:521` | `server/src/controllers/employeeController.ts` | `deleteSalaryPayment` | controllers | 37.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/expenseController.ts:buildExpenseUpdatePayload:264` | `server/src/controllers/expenseController.ts` | `buildExpenseUpdatePayload` | controllers | 37.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/inventoryController.ts:resolveOpeningWarehouse:101` | `server/src/controllers/inventoryController.ts` | `resolveOpeningWarehouse` | controllers | 37.1 | Still reported — CRAP 67.9 (cyc 11), coverage istanbul, partial |
| `health:server/src/controllers/inventoryController.ts:createStockTransfer:669` | `server/src/controllers/inventoryController.ts` | `createStockTransfer` | controllers | 37.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/inventoryController.ts:correctBatchReconciliation:1258` | `server/src/controllers/inventoryController.ts` | `correctBatchReconciliation` | controllers | 37.1 | Still reported — CRAP 132 (cyc 11), coverage istanbul, none |
| `health:server/src/controllers/ownerPersonalLoansController.ts:createBorrower:625` | `server/src/controllers/ownerPersonalLoansController.ts` | `createBorrower` | controllers | 37.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/paymentsController.ts:updatePayment:357` | `server/src/controllers/paymentsController.ts` | `updatePayment` | controllers | 37.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/supplierBillController.ts:listSupplierBills:10` | `server/src/controllers/supplierBillController.ts` | `listSupplierBills` | controllers | 37.1 | Still reported — CRAP 132 (cyc 11), coverage istanbul, none |
| `health:server/src/controllers/supplierPrepaymentController.ts:listSupplierPrepayments:10` | `server/src/controllers/supplierPrepaymentController.ts` | `listSupplierPrepayments` | controllers | 37.1 | Still reported — CRAP 132 (cyc 11), coverage istanbul, none |
| `health:server/src/controllers/supplierRefundController.ts:createSupplierRefund:63` | `server/src/controllers/supplierRefundController.ts` | `createSupplierRefund` | controllers | 37.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/Expense.ts:getAll:90` | `server/src/models/Expense.ts` | `getAll` | models | 37.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/Invoice.ts:<arrow>:903` | `server/src/models/Invoice.ts` | `<arrow>` | models | 37.1 | No longer reported — the function moved into extracted operations |
| `health:server/src/models/OwnerCapital.ts:getAll:85` | `server/src/models/OwnerCapital.ts` | `getAll` | models | 37.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/Payment.ts:<arrow>:685` | `server/src/models/Payment.ts` | `<arrow>` | models | 37.1 | No longer reported — the function moved into extracted operations |
| `health:server/src/models/Purchase.ts:transaction:651` | `server/src/models/Purchase.ts` | `transaction` | models | 37.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/Reports.ts:computeAPAging:317` | `server/src/models/Reports.ts` | `computeAPAging` | models | 37.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/Role.ts:update:80` | `server/src/models/Role.ts` | `update` | models | 37.1 | Still reported — CRAP 132 (cyc 11), coverage istanbul, none |
| `health:server/src/models/StockMovement.ts:run:1452` | `server/src/models/StockMovement.ts` | `run` | models | 37.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/StockReservation.ts:create:22` | `server/src/models/StockReservation.ts` | `create` | models | 37.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/services/backupService.ts:runBackup:145` | `server/src/services/backupService.ts` | `runBackup` | services | 37.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/services/invoiceReturnService.ts:processReturn:280` | `server/src/services/invoiceReturnService.ts` | `processReturn` | services | 37.1 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/scripts/fixtures/unapplied-cash-ui.cjs:<arrow>:47` | `server/scripts/fixtures/unapplied-cash-ui.cjs` | `<arrow>` | remaining | 110 | Still reported — CRAP 110 (cyc 10), coverage estimated, none |
| `health:server/scripts/lib/correctionSafety.ts:assertCorrectionAuthorized:56` | `server/scripts/lib/correctionSafety.ts` | `assertCorrectionAuthorized` | remaining | 110 | Still reported — CRAP 110 (cyc 10), coverage estimated, none |
| `health:server/src/__tests__/cashTruth.test.ts:it("an unpaid purchase contributes nothing t..."):68` | `server/src/__tests__/cashTruth.test.ts` | `it("an unpaid purchase contributes nothing t...")` | remaining | 31.6 | Still reported — CRAP 31.6 (cyc 10), coverage estimated, partial |
| `health:server/src/__tests__/reverseStockRestock.test.ts:it("return 2 then return 3 on same item; eac..."):442` | `server/src/__tests__/reverseStockRestock.test.ts` | `it("return 2 then return 3 on same item; eac...")` | remaining | 31.6 | Still reported — CRAP 31.6 (cyc 10), coverage estimated, partial |
| `health:server/src/controllers/customReportsController.ts:createReport:179` | `server/src/controllers/customReportsController.ts` | `createReport` | controllers | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/employeeController.ts:updateEmployee:141` | `server/src/controllers/employeeController.ts` | `updateEmployee` | controllers | 31.6 | Still reported — CRAP 110 (cyc 10), coverage istanbul, none |
| `health:server/src/controllers/employeeController.ts:trx:427` | `server/src/controllers/employeeController.ts` | `trx` | controllers | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/employeeController.ts:createLoan:751` | `server/src/controllers/employeeController.ts` | `createLoan` | controllers | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/inventoryController.ts:updateWarehouse:395` | `server/src/controllers/inventoryController.ts` | `updateWarehouse` | controllers | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/invoiceController.ts:getInvoices:125` | `server/src/controllers/invoiceController.ts` | `getInvoices` | controllers | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/invoiceController.ts:resolveUpdatedInvoiceStatus:301` | `server/src/controllers/invoiceController.ts` | `resolveUpdatedInvoiceStatus` | controllers | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/invoiceController.ts:transaction:779` | `server/src/controllers/invoiceController.ts` | `transaction` | controllers | 31.6 | Still reported — CRAP 156 (cyc 12), coverage istanbul, none |
| `health:server/src/controllers/invoiceReturnController.ts:settleReturn:13` | `server/src/controllers/invoiceReturnController.ts` | `settleReturn` | controllers | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/ownerPersonalLoansController.ts:<arrow>:197` | `server/src/controllers/ownerPersonalLoansController.ts` | `<arrow>` | controllers | 31.6 | No longer reported — the function moved into extracted operations |
| `health:server/src/controllers/ownerPersonalLoansController.ts:addRepayment:398` | `server/src/controllers/ownerPersonalLoansController.ts` | `addRepayment` | controllers | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/paymentsController.ts:createCustomerPayment:195` | `server/src/controllers/paymentsController.ts` | `createCustomerPayment` | controllers | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/paymentsController.ts:createPayment:296` | `server/src/controllers/paymentsController.ts` | `createPayment` | controllers | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/controllers/reportsController.ts:getCustomerStatements:29` | `server/src/controllers/reportsController.ts` | `getCustomerStatements` | controllers | 110 | Still reported — CRAP 110 (cyc 10), coverage istanbul, none |
| `health:server/src/migrations/backfillGlPreposting.ts:post:95` | `server/src/migrations/backfillGlPreposting.ts` | `post` | remaining | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/Customer.ts:create:159` | `server/src/models/Customer.ts` | `create` | models | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/MobileInvoice.ts:toInvoiceStatus:174` | `server/src/models/MobileInvoice.ts` | `toInvoiceStatus` | models | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/OwnerCapital.ts:update:154` | `server/src/models/OwnerCapital.ts` | `update` | models | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/Production.ts:normalizeOutputLines:135` | `server/src/models/Production.ts` | `normalizeOutputLines` | models | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/Production.ts:recordProduction:187` | `server/src/models/Production.ts` | `recordProduction` | models | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/Purchase.ts:writePurchaseRow:182` | `server/src/models/Purchase.ts` | `writePurchaseRow` | models | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/PurchaseReturn.ts:assertDispositionAllowed:527` | `server/src/models/PurchaseReturn.ts` | `assertDispositionAllowed` | models | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/StockMovement.ts:getStockBalances:899` | `server/src/models/StockMovement.ts` | `getStockBalances` | models | 31.6 | Still reported — CRAP 110 (cyc 10), coverage istanbul, none |
| `health:server/src/models/SupplierRefund.ts:creditNoteRefundable:75` | `server/src/models/SupplierRefund.ts` | `creditNoteRefundable` | models | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/models/UserPreferences.ts:parseRow:43` | `server/src/models/UserPreferences.ts` | `parseRow` | models | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/services/PaymentRecordingService.ts:<arrow>:36` | `server/src/services/PaymentRecordingService.ts` | `<arrow>` | services | 31.6 | No longer reported — the function moved into extracted operations |
| `health:server/src/services/cashService.ts:normalizeCashMethod:62` | `server/src/services/cashService.ts` | `normalizeCashMethod` | services | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/services/expressionValidator.ts:parseFactor:234` | `server/src/services/expressionValidator.ts` | `parseFactor` | services | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/services/forecastService.ts:computeForecastAccuracy:948` | `server/src/services/forecastService.ts` | `computeForecastAccuracy` | services | 31.6 | Still reported — CRAP 110 (cyc 10), coverage istanbul, none |
| `health:server/src/services/invoiceReturnService.ts:validateReturnLines:81` | `server/src/services/invoiceReturnService.ts` | `validateReturnLines` | services | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/services/paymentValidation.ts:validateCustomerPayment:64` | `server/src/services/paymentValidation.ts` | `validateCustomerPayment` | services | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/services/reportQueryEngine.ts:buildHavingClause:688` | `server/src/services/reportQueryEngine.ts` | `buildHavingClause` | services | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/services/returnMath.ts:validateAllocations:299` | `server/src/services/returnMath.ts` | `validateAllocations` | services | 31.6 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/services/unappliedCashService.ts:<arrow>:70` | `server/src/services/unappliedCashService.ts` | `<arrow>` | services | 31.6 | No longer reported — the function moved into extracted operations |
| `health:server/src/services/unappliedCashService.ts:<arrow>:128` | `server/src/services/unappliedCashService.ts` | `<arrow>` | services | 31.6 | No longer reported — the function moved into extracted operations |
| `health:server/src/scripts/backfill-batches.ts:backfillProductions:34` | `server/src/scripts/backfill-batches.ts` | `backfillProductions` | remaining | 90 | Still reported — CRAP 90 (cyc 9), coverage estimated, none |
| `health:server/scripts/dev/audit-trace.ts:testFullPayment:462` | `server/scripts/dev/audit-trace.ts` | `testFullPayment` | remaining | 72 | Still reported — CRAP 72 (cyc 8), coverage estimated, none |
| `health:server/scripts/dev/audit-trace.ts:testCustomerStatement:1177` | `server/scripts/dev/audit-trace.ts` | `testCustomerStatement` | remaining | 56 | Still reported — CRAP 56 (cyc 7), coverage estimated, none |
| `health:server/scripts/recompute-item-amounts.js:main:65` | `server/scripts/recompute-item-amounts.js` | `main` | remaining | 56 | Still reported — CRAP 56 (cyc 7), coverage estimated, none |
| `health:server/scripts/repair-stock.ts:repairOrphanedBatches:181` | `server/scripts/repair-stock.ts` | `repairOrphanedBatches` | remaining | 56 | Still reported — CRAP 56 (cyc 7), coverage estimated, none |
| `health:server/src/models/Reports.ts:getCustomerStatements:14` | `server/src/models/Reports.ts` | `getCustomerStatements` | models | 56 | Still reported — CRAP 56 (cyc 7), coverage istanbul, none |
| `health:docs/superpowers/verification/unapplied-cash-stage-d.cjs:main:76` | `docs/superpowers/verification/unapplied-cash-stage-d.cjs` | `main` | remaining | 42 | Still reported — CRAP 42 (cyc 6), coverage estimated, none |
| `health:server/scripts/backfill-ledger-dates.js:main:37` | `server/scripts/backfill-ledger-dates.js` | `main` | remaining | 42 | Still reported — CRAP 42 (cyc 6), coverage estimated, none |
| `health:server/scripts/dev/audit-trace.ts:testPartialPayment:569` | `server/scripts/dev/audit-trace.ts` | `testPartialPayment` | remaining | 42 | Still reported — CRAP 42 (cyc 6), coverage estimated, none |
| `health:server/scripts/dev/audit-trace.ts:testReturnWithFee:645` | `server/scripts/dev/audit-trace.ts` | `testReturnWithFee` | remaining | 42 | Still reported — CRAP 42 (cyc 6), coverage estimated, none |
| `health:server/scripts/dev/audit-trace.ts:testTransferBug:1061` | `server/scripts/dev/audit-trace.ts` | `testTransferBug` | remaining | 42 | Still reported — CRAP 42 (cyc 6), coverage estimated, none |
| `health:server/scripts/recompute-item-amounts.js:computeLineAmount:34` | `server/scripts/recompute-item-amounts.js` | `computeLineAmount` | remaining | 42 | Still reported — CRAP 42 (cyc 6), coverage estimated, none |
| `health:server/src/models/Supplier.ts:create:127` | `server/src/models/Supplier.ts` | `create` | models | 42 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:server/src/scripts/reconcile-stock-cash.ts:flagUnbatchableStock:44` | `server/src/scripts/reconcile-stock-cash.ts` | `flagUnbatchableStock` | remaining | 42 | Still reported — CRAP 42 (cyc 6), coverage estimated, none |
| `health:server/src/services/activityLogger.ts:logWithRequest:268` | `server/src/services/activityLogger.ts` | `logWithRequest` | services | 42 | No longer reported — still present and now under the CRAP cut-off (coverage or complexity) |
| `health:docs/superpowers/verification/unapplied-customer-payments.cjs:fixture:76` | `docs/superpowers/verification/unapplied-customer-payments.cjs` | `fixture` | remaining | 30 | Still reported — CRAP 30 (cyc 5), coverage estimated, none |
| `health:server/scripts/apply-customer15-correction.ts:<arrow>:145` | `server/scripts/apply-customer15-correction.ts` | `<arrow>` | remaining | 30 | Still reported — CRAP 30 (cyc 5), coverage estimated, none |
| `health:server/scripts/dedupe-po.js:main:40` | `server/scripts/dedupe-po.js` | `main` | remaining | 30 | Still reported — CRAP 30 (cyc 5), coverage estimated, none |
| `health:server/scripts/dedupe-po.js:tx:101` | `server/scripts/dedupe-po.js` | `tx` | remaining | 30 | Still reported — CRAP 30 (cyc 5), coverage estimated, none |
| `health:server/scripts/recompute-item-amounts.js:parseCurrency:28` | `server/scripts/recompute-item-amounts.js` | `parseCurrency` | remaining | 30 | Still reported — CRAP 30 (cyc 5), coverage estimated, none |
| `health:server/scripts/reconcile-customer-credits.ts:main:15` | `server/scripts/reconcile-customer-credits.ts` | `main` | remaining | 30 | Still reported — CRAP 30 (cyc 5), coverage estimated, none |
| `health:server/scripts/rollback-customer15-correction.ts:<arrow>:39` | `server/scripts/rollback-customer15-correction.ts` | `<arrow>` | remaining | 30 | Still reported — CRAP 30 (cyc 5), coverage estimated, none |
| `health:server/server.ts:getLocalIP:105` | `server/server.ts` | `getLocalIP` | remaining | 30 | Still reported — CRAP 30 (cyc 5), coverage estimated, none |
| `health:server/src/models/ActivityLog.ts:getStats:245` | `server/src/models/ActivityLog.ts` | `getStats` | models | 30 | Still reported — CRAP 30 (cyc 5), coverage istanbul, none |
| `health:server/src/models/Supplier.ts:safeSortBy:69` | `server/src/models/Supplier.ts` | `safeSortBy` | models | 30 | Still reported — CRAP 30 (cyc 5), coverage istanbul, none |
| `health:server/src/models/Supplier.ts:getLedger:177` | `server/src/models/Supplier.ts` | `getLedger` | models | 30 | Still reported — CRAP 30 (cyc 5), coverage istanbul, none |
| `health:server/src/scripts/fix-duplicate-purchase.ts:fix:56` | `server/src/scripts/fix-duplicate-purchase.ts` | `fix` | remaining | 30 | Still reported — CRAP 30 (cyc 5), coverage estimated, none |
| `health:server/src/services/forecastService.ts:calculateHolts:157` | `server/src/services/forecastService.ts` | `calculateHolts` | services | 30 | Still reported — CRAP 30 (cyc 5), coverage istanbul, none |

## D. Findings introduced by this remediation

Every operation extracted during the cleanup was checked against the final scan and the
`fallow audit --base HEAD` attribution pass. A post-commit reconciliation against the
original inventory found six additional named symbols (D.1b), two anonymous arrow
findings, and 72 pre-existing functions newly reported by the corrected coverage
mapping (D.2). These were absent from the first version of this section and are recorded
here rather than omitted:

| New symbol | File | Why it exists |
|---|---|---|
| `productionRequestError`, `jointOutputRequestError` | `server/src/controllers/productionController.ts` | Request guards for `recordProduction`; original 400 precedence preserved |
| `recordMultiItemPurchase`, `recordSingleItemPurchase` | `server/src/controllers/purchaseController.ts` | The two write paths of `recordPurchase`; idempotency claim and validation order unchanged |
| `employeeForRequest` | `server/src/controllers/employeeController.ts` | Resolve `:id` → employee with the standard 404 |
| `borrowerRequestContext` | `server/src/controllers/ownerPersonalLoansController.ts` | Resolve `:id` → borrower + acting user with the standard 404 |
| `listRequestQuery` | `server/src/utils/controllerPagination.ts` | Shared list request parsing (search, sort, pagination) |
| `toCashTransaction` | `server/src/services/cashService.ts` | Map one cash-flow row; per-source type label and sign stay at the call site |
| `purchaseMatchesReceipt`, `poPaidTotal`, `logDuplicatePurchase` | `server/src/scripts/reconcile-stock-cash.ts` | Stages of duplicate-purchase detection |
| `snapshotErrorMessage`, `removeQuietly`, `closeQuietly` | `server/scripts/backup-db.js` | Branch-absorbing helpers that keep `createSnapshot` under the CRAP threshold |

### D.1b New symbols found by post-commit reconciliation

The named symbols below are absent from the fixed point (`212a9fa7`) and were not in the
first version of this section. The two anonymous arrow findings are new relative to the
original inventory but cannot be name-matched; they are included so the scan delta is
complete. All eight are still reported by the final scan; their measured status is
recorded rather than claimed cleared.

| Symbol | Path:line | Owner | Final scan | Status |
|---|---|---|---|---|
| `updateBorrowerFields` | `server/src/controllers/ownerPersonalLoansController.ts:695` | controllers | CRAP 90 (cyc 9/cog 8; istanbul) | New symbol; absent at 212a9fa7; still reported |
| `validateReportSort` | `server/src/controllers/customReportsController.ts:97` | controllers | CRAP 35 (cyc 8/cog 12; istanbul) | New symbol; absent at 212a9fa7; still reported |
| `parseGuardOption` | `scripts/openspec-archive-guard.js:58` | scripts | CRAP 30 (cyc 5/cog 5; estimated) | New symbol; absent at 212a9fa7; still reported |
| `verifySnapshot` | `server/scripts/backup-db.js:82` | scripts | CRAP 30 (cyc 5/cog 5; estimated) | New symbol; absent at 212a9fa7; still reported |
| `postReconciledStock` | `server/scripts/repair-stock.ts:90` | scripts | CRAP 30 (cyc 5/cog 5; estimated) | New symbol; absent at 212a9fa7; still reported |
| `postCoverageAdjustment` | `server/src/config/database.ts:1262` | config | CRAP 30 (cyc 5/cog 5; istanbul) | New symbol; absent at 212a9fa7; still reported |
| `<arrow>` | `server/src/models/Employee.ts:405` | models | CRAP 72 (cyc 8/cog 9; istanbul) | Anonymous callback; new relative to the inventory; still reported |
| `<arrow>` | `server/src/models/Reports.ts:1241` | models | CRAP 56 (cyc 7/cog 10; istanbul) | Anonymous callback; new relative to the inventory; still reported |

### D.2 Pre-existing functions newly reported by the remapped coverage (72)

These symbol names (or their semantically equivalent registrations, allowing quote and
trailing-parenthesis rendering differences) are present at the fixed point (`212a9fa7`)
and were not part of the original 340-entry report. They are surfaced by the test-only
source maps and measured coverage; they are not introduced by the extraction. All are
recorded with their final measured CRAP so the scan delta is not silent.

| File:line | Symbol | Owner | Final scan | Why now |
|---|---|---|---|---|
| `server/src/controllers/accountingController.ts:131` | `getAccountBalance` | controllers | CRAP 30 (cyc 5/cog 4; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/accountingController.ts:208` | `getPeriod` | controllers | CRAP 30 (cyc 5/cog 4; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/customersController.ts:214` | `getCustomerStatement` | controllers | CRAP 72 (cyc 8/cog 7; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/dashboardController.ts:21` | `getSummary` | controllers | CRAP 72 (cyc 8/cog 5; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/dashboardController.ts:141` | `getKPIBatch` | controllers | CRAP 90 (cyc 9/cog 7; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/dashboardController.ts:303` | `saveCashOpeningBalances` | controllers | CRAP 42 (cyc 6/cog 6; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/dashboardLayoutController.ts:49` | `createLayout` | controllers | CRAP 30 (cyc 5/cog 5; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/dashboardLayoutController.ts:108` | `renameLayout` | controllers | CRAP 56 (cyc 7/cog 6; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/dashboardLayoutController.ts:204` | `duplicateLayout` | controllers | CRAP 30 (cyc 5/cog 4; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/employeeController.ts:45` | `getEmployees` | controllers | CRAP 72 (cyc 8/cog 7; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/employeeController.ts:187` | `deleteEmployee` | controllers | CRAP 30 (cyc 5/cog 3; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/employeeController.ts:535` | `getSalaryMonthDetail` | controllers | CRAP 30 (cyc 5/cog 4; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/employeeController.ts:1016` | `deleteLoan` | controllers | CRAP 42 (cyc 6/cog 5; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/expenseController.ts:427` | `createExpenseCategory` | controllers | CRAP 42 (cyc 6/cog 7; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/expenseController.ts:446` | `updateExpenseCategory` | controllers | CRAP 42 (cyc 6/cog 8; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/expenseController.ts:469` | `deleteExpenseCategory` | controllers | CRAP 42 (cyc 6/cog 7; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/inventoryController.ts:761` | `getStockBalances` | controllers | CRAP 42 (cyc 6/cog 5; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/inventoryController.ts:856` | `recordPhysicalCountItem` | controllers | CRAP 42 (cyc 6/cog 5; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/inventoryController.ts:1301` | `updateBatchStatus` | controllers | CRAP 30 (cyc 5/cog 4; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/inventoryController.ts:1357` | `releaseReservation` | controllers | CRAP 42 (cyc 6/cog 5; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/invoiceController.ts:859` | `restoreInvoice` | controllers | CRAP 42 (cyc 6/cog 5; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/mobileInvoiceController.ts:71` | `getDraft` | controllers | CRAP 30 (cyc 5/cog 4; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/ownerEquityController.ts:145` | `getCapitalList` | controllers | CRAP 42 (cyc 6/cog 5; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/ownerEquityController.ts:384` | `getWithdrawalList` | controllers | CRAP 42 (cyc 6/cog 5; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/ownerEquityController.ts:512` | `voidWithdrawal` | controllers | CRAP 42 (cyc 6/cog 4; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/posController.ts:336` | `getPOSTransactions` | controllers | CRAP 30 (cyc 5/cog 4; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/purchaseOrderController.ts:186` | `addLineItem` | controllers | CRAP 90 (cyc 9/cog 8; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/purchaseOrderController.ts:220` | `updateLineItem` | controllers | CRAP 72 (cyc 8/cog 8; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/purchaseOrderController.ts:452` | `getSummaryBySupplier` | controllers | CRAP 42 (cyc 6/cog 5; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/reportsController.ts:107` | `getCashFlowReport` | controllers | CRAP 42 (cyc 6/cog 5; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/reportsController.ts:164` | `saveCashReconciliation` | controllers | CRAP 56 (cyc 7/cog 6; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/reportsController.ts:193` | `getExpiryReport` | controllers | CRAP 30 (cyc 5/cog 4; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/rolesController.ts:70` | `updateRole` | controllers | CRAP 42 (cyc 6/cog 8; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/rolesController.ts:125` | `deleteRole` | controllers | CRAP 42 (cyc 6/cog 8; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/settingsController.ts:33` | `updateSetting` | controllers | CRAP 30 (cyc 5/cog 4; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/suppliersController.ts:22` | `getSuppliers` | controllers | CRAP 56 (cyc 7/cog 6; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/suppliersController.ts:128` | `updateSupplier` | controllers | CRAP 56 (cyc 7/cog 6; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/suppliersController.ts:290` | `getSupplierLedger` | controllers | CRAP 72 (cyc 8/cog 7; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/suppliersController.ts:323` | `getSupplierStatement` | controllers | CRAP 90 (cyc 9/cog 8; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/controllers/userController.ts:173` | `deleteUser` | controllers | CRAP 36.8 (cyc 9/cog 8; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/migrations/backfillGlPreposting.ts:277` | `backfill7GoodsReceipts` | migrations | CRAP 33 (cyc 9/cog 11; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/models/ActivityLog.ts:69` | `insert` | models | CRAP 42 (cyc 6/cog 5; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/models/ActivityLog.ts:365` | `rows` | models | CRAP 30 (cyc 5/cog 4; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/models/BOM.ts:296` | `transaction` | models | CRAP 30 (cyc 5/cog 5; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/models/Customer.ts:341` | `getStatement` | models | CRAP 30 (cyc 5/cog 5; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/models/CustomReport.ts:69` | `update` | models | CRAP 30 (cyc 5/cog 4; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/models/Employee.ts:241` | `getAll` | models | CRAP 56 (cyc 7/cog 7; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/models/Employee.ts:469` | `getAdvanceCarryover` | models | CRAP 90 (cyc 9/cog 13; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/models/Expense.ts:318` | `updateCategory` | models | CRAP 30 (cyc 5/cog 5; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/models/MobileInvoice.ts:78` | `createDraft` | models | CRAP 56 (cyc 7/cog 6; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/models/MobileInvoice.ts:96` | `updateDraft` | models | CRAP 72 (cyc 8/cog 7; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/models/OwnerCapital.ts:119` | `getCount` | models | CRAP 56 (cyc 7/cog 6; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/models/OwnerWithdrawal.ts:368` | `getCount` | models | CRAP 90 (cyc 9/cog 8; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/models/PhysicalCount.ts:182` | `getAll` | models | CRAP 72 (cyc 8/cog 7; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/models/Reports.ts:693` | `getExpiryReport` | models | CRAP 56 (cyc 7/cog 6; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/models/Reports.ts:1179` | `rows` | models | CRAP 90 (cyc 9/cog 5; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/models/Role.ts:62` | `create` | models | CRAP 30 (cyc 5/cog 5; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/models/Settings.ts:73` | `transaction` | models | CRAP 30 (cyc 5/cog 6; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/models/Supplier.ts:79` | `getAll` | models | CRAP 90 (cyc 9/cog 10; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/models/Supplier.ts:145` | `update` | models | CRAP 90 (cyc 9/cog 9; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/models/Supplier.ts:219` | `getStatement` | models | CRAP 30 (cyc 5/cog 5; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/routes/integrations.ts:23` | `router.put("/settings/:service")` | routes | CRAP 30 (cyc 5/cog 6; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/services/forecastService.ts:181` | `calculateHoltWinters` | services | CRAP 42 (cyc 6/cog 5; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/services/forecastService.ts:231` | `calculateSimpleARIMA` | services | CRAP 42 (cyc 6/cog 5; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/services/forecastService.ts:330` | `detectTrend` | services | CRAP 40.7 (cyc 7/cog 7; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/services/forecastService.ts:810` | `getDashboardData` | services | CRAP 42 (cyc 6/cog 4; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/services/forecastService.ts:868` | `getTrendData` | services | CRAP 56 (cyc 7/cog 6; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/services/forecastService.ts:1112` | `applyOverride` | services | CRAP 72 (cyc 8/cog 6; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/services/forecastService.ts:1234` | `createSeasonalEvent` | services | CRAP 30 (cyc 5/cog 4; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/services/invoiceReturnService.ts:1229` | `applyLegacyAdjust` | services | CRAP 90 (cyc 9/cog 10; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/services/reportQueryEngine.ts:610` | `buildBetween` | services | CRAP 56 (cyc 7/cog 6; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |
| `server/src/utils/errorMessage.ts:45` | `errorCode` | utils | CRAP 30 (cyc 5/cog 4; istanbul) | Symbol present at 212a9fa7; newly reported by the remapped coverage; not introduced by extraction |

None of the D.1 symbols exceeds cyclomatic 20 / cognitive 15 and none is reported as a
new clone group. The D.1b symbols are all still reported by the final scan (CRAP 30–90);
they are recorded with their measured status rather than claimed cleared. The D.2 rows
are pre-existing functions newly reported by the corrected coverage mapping; they are
not caused by the extraction and are recorded, not suppressed.

**One diff-risk warning remains, recorded rather than silenced:** `server/src/middleware/rateLimiter.ts:15`
`test-only-branch` (warn) — the rate-limiter consolidation moved the existing
`process.env.NODE_ENV` checks into a shared `sensitiveOperationOptions()` factory, so the
diff shows them as added lines. The check itself existed at HEAD with identical semantics
(test/development get a huge limit, development skips limiting); the route-specific
keys, limits, windows and messages are unchanged. The gate reports it as a warning and
exits 0.

## E. Verification

| Gate | Command | Result |
|---|---|---|
| Typecheck | `npm run typecheck` (server/) | exit 0 |
| Lint | `npm run lint` (server/) | exit 0 |
| Reversal rules | `npm run verify:reversal-rules` (server/) | exit 0 |
| Full server suite + mapped coverage | `npm test -- --coverage` (server/) | 168/169 suites, 1496/1497 tests passed. `supplierPurchasesFilter.test.ts` hit its 10 s test timeout under load; that suite passed 3/3 on isolated re-run and its coverage was merged. No clean full-suite run is recorded. |
| Final Fallow scan | `npx --yes fallow@3.34.1 --format json` | structural 0, clone groups 4 (all retained above) |
| Diff gate (CI) | `npx --yes fallow@3.34.1 audit --base HEAD` | see `.omo/evidence/task-7-audit-gate-final.log` |

Flutter was intentionally not rerun: no client code, route contract or shared API
shape changed, so `flutter analyze` / `flutter test` would not have observed a difference.
