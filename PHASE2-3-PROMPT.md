# Item Expiry Tracking — Phase 2 & 3 Implementation Prompt

> **Context:** You are implementing the Flutter frontend (Phase 2) and Reports/Alerts (Phase 3) for an item expiry tracking feature in a mini-ERP system. Phase 1 (DB + server) is being built in parallel — the backend APIs you need are either already exist or will exist by the time you integrate.

> **Spec file:** Read `item-expiry-spec.md` in the project root for the full specification. Your work is sections 4 (Frontend), 3.1-3.2 (API endpoints for reports), and 8 (Testing).

---

## What Already Exists (don't change these)

- `lib/data/models/item.dart` — Item model (you'll add 2 fields)
- `lib/data/models/invoice.dart` — Invoice/InvoiceItem models (you'll add fields)
- `lib/features/inventory/item_form_dialog.dart` — Item create/edit form (you'll add fields)
- `lib/features/purchases/purchase_form_dialog.dart` — Purchase form (you'll add expiry picker)
- `lib/features/invoices/invoice_detail_dialog.dart` — Invoice detail (you'll add expiry info)
- `lib/features/inventory/item_detail_dialog.dart` — Item detail dialog (you'll add expiry summary)
- `lib/features/reports/batch_traceability_report_screen.dart` — Existing report (you'll add columns)
- `lib/data/repositories/inventory_repository.dart` — Inventory API calls (you'll add batch endpoints)
- `lib/l10n/app_localizations_en.dart` — English strings
- `lib/l10n/app_localizations_ur.dart` — Urdu strings
- `server/src/models/StockMovement.ts` — Has `consumeFromOldestBatches` (Phase 1 adds FEFO)
- `server/src/models/Purchase.ts` — Has `recordPurchase` (Phase 1 adds expiry_date param)
- `server/src/models/PurchaseOrder.ts` — Has `addReceipt` (Phase 1 adds expiry_date)
- `server/src/models/Production.ts` — Has `recordProduction` (Phase 1 adds expiry_date)
- `server/src/models/Invoice.ts` — Has `createInvoice` (Phase 1 adds expiry_notes)
- Batch management does NOT exist yet — you're creating it

## Architecture Context

- **Frontend:** Flutter with Riverpod state management
- **Backend:** Node.js + Express + TypeScript + SQLite (better-sqlite3)
- **Grid:** PlutoGrid for desktop lists
- **Forms:** Custom `FormFieldShell`, `SearchableSelect`, `FormSectionCard` widgets
- **Localization:** `AppLocalizations.of(context)!` pattern — all strings must be in both en and ur
- **Repository pattern:** API calls go through `lib/data/repositories/` providers
- **State:** Riverpod providers in `lib/features/*/` directories
- **Date picker:** Use existing `lib/widgets/date_picker.dart` → `pickDate()` helper
- **Toast:** Use `lib/widgets/app_toast.dart` → `showAppToast()`
- **Form helpers:** `lib/widgets/form_helpers.dart` → `formInputDecoration()`, `numText()`, `submitOnEnter()`
- **Type helpers:** `lib/data/models/json_helpers.dart` → `asInt()`, `asString()`, `asNum()`, `asBool()`

## API Endpoints You Can Use (being built in parallel)

```
# Batch management
GET    /api/stock-batches?item_id=&warehouse_id=   — list batches (includes new fields)
PATCH  /api/stock-batches/:id                       — update expiry_date
PATCH  /api/stock-batches/:id/halt                  — set halted=1, halted_reason
PATCH  /api/stock-batches/:id/unhalt                — set halted=0

# Items (already exist, new fields added)
GET    /api/inventory/items/:id                     — now includes has_expiry, near_expiry_threshold_days
POST   /api/inventory/items                         — now accepts has_expiry, near_expiry_threshold_days
PUT    /api/inventory/items/:id                     — now accepts has_expiry, near_expiry_threshold_days

# Invoices (already exist, new fields added)
GET    /api/invoices/:id                            — now includes expiry_notes, items now include expiry_date, is_expired_at_sale

# Reports (Phase 3)
GET    /api/reports/expiry?warehouse_id=&threshold_days=&status=   — expiry report data
GET    /api/dashboard/expiry-alerts?days=30                        — dashboard alerts data

# Existing endpoints that now accept expiry_date in request body
POST   /api/purchases                               — now accepts optional expiry_date
POST   /api/purchase-orders/:id/receipts            — reads expiry_date from PO item
PUT    /api/purchase-orders/:id                     — PO items now accept optional expiry_date
POST   /api/productions                             — now accepts optional expiry_date
```

---

## Phase 2 Tasks — Frontend Core

### Task 2.1: Update Item Model
**File:** `lib/data/models/item.dart`

Add two fields to the `Item` class:
```dart
final bool hasExpiry;
final num? nearExpiryThresholdDays;
```

In `fromJson`, add:
```dart
hasExpiry: asBool(json['has_expiry']),
nearExpiryThresholdDays: asNum(json['near_expiry_threshold_days']),
```

In `toJson`, add:
```dart
'has_expiry': hasExpiry ? 1 : 0,
if (nearExpiryThresholdDays != null) 'near_expiry_threshold_days': nearExpiryThresholdDays,
```

Add to constructor params (after `isActive`):
```dart
this.hasExpiry = false,
this.nearExpiryThresholdDays,
```

### Task 2.2: Create/Update StockBatch Model
**File:** `lib/data/models/stock_batch.dart` (create if not exists)

```dart
import '../models/json_helpers.dart';

enum BatchStatus {
  normal('normal'),
  nearExpiry('near_expiry'),
  expired('expired'),
  halted('halted');

  const BatchStatus(this.value);
  final String value;
  static BatchStatus fromString(Object? value) =>
      values.firstWhere((e) => e.value == value, orElse: () => BatchStatus.normal);
}

class StockBatch {
  const StockBatch({
    required this.id,
    required this.batchNo,
    required this.itemId,
    required this.warehouseId,
    required this.sourceType,
    required this.sourceId,
    required this.quantityOriginal,
    required this.quantityRemaining,
    required this.unitCost,
    required this.receivedDate,
    this.expiryDate,
    this.halted = false,
    this.haltedReason,
    // Joined fields
    this.itemCode,
    this.itemName,
    this.warehouseCode,
    this.warehouseName,
    this.sourceNo,
  });

  factory StockBatch.fromJson(Map<String, dynamic> json) => StockBatch(
    id: asInt(json['id']) ?? 0,
    batchNo: asString(json['batch_no']) ?? '',
    itemId: asInt(json['item_id']) ?? 0,
    warehouseId: asInt(json['warehouse_id']) ?? 0,
    sourceType: asString(json['source_type']) ?? '',
    sourceId: asInt(json['source_id']) ?? 0,
    quantityOriginal: asNum(json['quantity_original']) ?? 0,
    quantityRemaining: asNum(json['quantity_remaining']) ?? 0,
    unitCost: asNum(json['unit_cost']) ?? 0,
    receivedDate: asString(json['received_date']) ?? '',
    expiryDate: asString(json['expiry_date']),
    halted: asBool(json['halted']),
    haltedReason: asString(json['halted_reason']),
    itemCode: asString(json['item_code']),
    itemName: asString(json['item_name']),
    warehouseCode: asString(json['warehouse_code']),
    warehouseName: asString(json['warehouse_name']),
    sourceNo: asString(json['source_no']),
  );

  // Computed status — requires knowing today's date and a threshold
  BatchStatus computeStatus({num nearExpiryThresholdDays = 30}) {
    if (halted) return BatchStatus.halted;
    if (expiryDate == null) return BatchStatus.normal;
    final expiry = DateTime.tryParse(expiryDate!);
    if (expiry == null) return BatchStatus.normal;
    final now = DateTime.now();
    if (expiry.isBefore(now)) return BatchStatus.expired;
    if (expiry.difference(now).inDays <= nearExpiryThresholdDays) return BatchStatus.nearExpiry;
    return BatchStatus.normal;
  }

  bool get isExpired {
    if (expiryDate == null) return false;
    final expiry = DateTime.tryParse(expiryDate!);
    return expiry != null && expiry.isBefore(DateTime.now());
  }

  final int id;
  final String batchNo;
  final int itemId;
  final int warehouseId;
  final String sourceType;
  final int sourceId;
  final num quantityOriginal;
  final num quantityRemaining;
  final num unitCost;
  final String receivedDate;
  final String? expiryDate;
  final bool halted;
  final String? haltedReason;
  final String? itemCode;
  final String? itemName;
  final String? warehouseCode;
  final String? warehouseName;
  final String? sourceNo;
}
```

### Task 2.3: Update Invoice Model
**File:** `lib/data/models/invoice.dart`

Add to `Invoice` class:
```dart
final String? expiryNotes;
```

In `Invoice.fromJson`, add:
```dart
expiryNotes: asString(json['expiry_notes']),
```

Add to `toJson`:
```dart
if (expiryNotes != null) 'expiry_notes': expiryNotes,
```

Add to `InvoiceItem` class:
```dart
final String? expiryDate;
final bool isExpiredAtSale;
```

In `InvoiceItem.fromJson`, add:
```dart
expiryDate: asString(json['expiry_date']),
isExpiredAtSale: asBool(json['is_expired_at_sale']),
```

### Task 2.4: Item Form — Add Expiry Toggle
**File:** `lib/features/inventory/item_form_dialog.dart`

Add state variables (after `_isManufactured`):
```dart
bool _hasExpiry = false;
num? _nearExpiryThresholdDays;
late TextEditingController _thresholdController;
```

In `initState`, initialize:
```dart
_hasExpiry = item?.hasExpiry ?? false;
_nearExpiryThresholdDays = item?.nearExpiryThresholdDays;
_thresholdController = TextEditingController(
  text: numText(item?.nearExpiryThresholdDays ?? 30),
);
```

In `dispose`, add `_thresholdController.dispose()`.

In `_buildBody()`, add:
```dart
'has_expiry': _hasExpiry,
if (_hasExpiry && _thresholdController.text.isNotEmpty)
  'near_expiry_threshold_days': int.parse(_thresholdController.text),
```

In the form's `Column` children, after the "Item Type" section and before "Description", add:
```dart
const SizedBox(height: 10),
FormFieldShell(
  label: 'Expiry Tracking',
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text('Track expiry dates', style: Theme.of(context).textTheme.bodyMedium),
        value: _hasExpiry,
        onChanged: _submitting ? null : (v) => setState(() => _hasExpiry = v),
      ),
      if (_hasExpiry) ...[
        const SizedBox(height: 8),
        FormFieldShell(
          label: 'Near-expiry threshold (days)',
          child: TextFormField(
            controller: _thresholdController,
            enabled: !_submitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            decoration: formInputDecoration(),
            validator: (v) {
              if (!_hasExpiry) return null;
              final n = int.tryParse(v?.trim() ?? '');
              if (n == null || n <= 0) return 'Must be a positive number';
              return null;
            },
          ),
        ),
      ],
    ],
  ),
),
```

### Task 2.5: Purchase Form — Add Expiry Date Picker
**File:** `lib/features/purchases/purchase_form_dialog.dart`

Add state variable:
```dart
DateTime? _expiryDate;
```

Add a helper method:
```dart
Future<void> _pickExpiryDate() async {
  final picked = await pickDate(
    context,
    initialDate: _expiryDate,
    firstDate: DateTime.now(),
  );
  if (picked != null) setState(() => _expiryDate = picked);
}
```

In the item section (after quantity/cost row), add expiry date picker:
```dart
// Only show if selected item has expiry tracking
final selectedItems = ref.watch(allItemsProvider).valueOrNull ?? [];
final selectedItem = selectedItems.where((i) => i.id == _itemId).firstOrNull;
if (selectedItem?.hasExpiry == true) ...[
  const SizedBox(height: 12),
  FormFieldShell(
    label: 'Expiry Date',
    child: SizedBox(
      height: 42,
      child: OutlinedButton.icon(
        onPressed: _busy ? null : _pickExpiryDate,
        icon: const Icon(Icons.calendar_today_outlined, size: 15),
        label: Text(
          _expiryDate != null
              ? Formatters.date(isoDate(_expiryDate!))
              : 'Select date (optional)',
        ),
      ),
    ),
  ),
],
```

In the submit body, include:
```dart
if (_expiryDate != null) 'expiry_date': isoDate(_expiryDate!),
```

### Task 2.6: PO Form — Add Expiry Date to Item Lines
**File:** `lib/features/purchase_orders/purchase_order_form.dart` (or the equivalent PO creation dialog)

Similar pattern to Task 2.5 — add an expiry date picker to each PO item line. When the item has `has_expiry = true`, show the picker. The value is sent in the PO items array as `expiry_date`.

### Task 2.7: Production Form — Add Expiry Date
**File:** `lib/features/production/production_form.dart`

Add an optional expiry date field for the output item. Only shown when the output item has `has_expiry = true`. Send as `expiry_date` in the production request body.

### Task 2.8: Batch Management Screen (NEW)
**File:** `lib/features/inventory/batch_management_screen.dart` (create new)

This is the most substantial new screen. Create a `ConsumerWidget` that:

1. **Item selector** at the top — dropdown to pick an item
2. **PlutoGrid** showing all batches for the selected item:
   - Columns: Batch No, Warehouse, Source, Qty Original, Qty Remaining, Unit Cost, Received Date, Expiry Date (editable), Status (badge), Actions
3. **Status badges** — color-coded:
   - 🟢 Normal: green chip
   - 🟡 Near-Expiry: yellow/orange chip
   - 🔴 Expired: red chip
   - ⬜ Halted: gray chip with "Halted" text
4. **Inline expiry editing** — tap the Expiry Date cell to edit via date picker
5. **Halt/Unhalt button** in Actions column — toggles halt status
6. **Halt reason dialog** — when halting, show a dialog to optionally enter a reason

API calls needed:
- `GET /api/stock-batches?item_id=X` — fetch batches
- `PATCH /api/stock-batches/:id` — update expiry_date
- `PATCH /api/stock-batches/:id/halt` — halt with reason
- `PATCH /api/stock-batches/:id/unhalt` — unhalt

Add this screen to the inventory navigation (accessible from Inventory sidebar or item detail dialog).

### Task 2.9: Invoice Detail — Expiry Info
**File:** `lib/features/invoices/invoice_detail_dialog.dart`

1. On each invoice item row, if `item.expiryDate != null`:
   - Show a small icon: ⚠️ if `isExpiredAtSale`, 🕐 if near-expiry
   - Tooltip or tap shows: "Expiry: DD/MM/YYYY"
   - If expired: "Sold X days after expiry"

2. If `invoice.expiryNotes != null`, show a styled `Card` at the bottom (before or after user notes):
   ```dart
   Container(
     padding: EdgeInsets.all(12),
     decoration: BoxDecoration(
       color: hasExpired ? Colors.red.shade50 : Colors.orange.shade50,
       borderRadius: BorderRadius.circular(8),
       border: Border.all(color: hasExpired ? Colors.red.shade200 : Colors.orange.shade200),
     ),
     child: Text(invoice.expiryNotes!, ...),
   )
   ```

### Task 2.10-2.11: POS/Sales Order Expiry Warnings
**Files:** `lib/features/pos/`, `lib/features/sales/`

When a sale is being processed and the consumed batch is expired or near-expiry:
- **Near-expiry:** Show `showAppToast()` with warning icon
- **Expired:** Show a `showDialog()` confirmation: "This item expired X days ago. Are you sure you want to sell it?"

This requires the FEFO consumption response to include expiry info. If the server doesn't return this yet, add a client-side check: after items are selected, check their batch expiry dates via the batch API.

### Task 2.12: Item Detail — Batch Expiry Summary
**File:** `lib/features/inventory/item_detail_dialog.dart`

In the stock-by-warehouse section, add a summary line:
```
"Batches: 5 total, 2 near-expiry, 1 expired"
```
With a "Manage Batches" button that opens the batch management screen (Task 2.8).

### Task 2.13: Inventory Repository — Batch API Calls
**File:** `lib/data/repositories/inventory_repository.dart`

Add methods:
```dart
Future<ApiResult<List<StockBatch>>> getBatches({int? itemId, int? warehouseId});
Future<ApiResult<void>> updateBatchExpiry(int batchId, String? expiryDate);
Future<ApiResult<void>> haltBatch(int batchId, {String? reason});
Future<ApiResult<void>> unhaltBatch(int batchId);
```

### Tasks 2.14-2.15: Localization Strings
Add to both `app_localizations_en.dart` and `app_localizations_ur.dart`:

```dart
// Expiry-related strings
'expiryTracking': 'Expiry Tracking' / 'مinoxpiry tracking',
'trackExpiryDates': 'Track expiry dates',
'nearExpiryThreshold': 'Near-expiry threshold (days)',
'batchManagement': 'Batch Management',
'expiryDate': 'Expiry Date',
'expiryStatus': 'Expiry Status',
'statusNormal': 'Normal',
'statusNearExpiry': 'Near Expiry',
'statusExpired': 'Expired',
'statusHalted': 'Halted',
'haltBatch': 'Halt Batch',
'unhaltBatch': 'Unhalt Batch',
'haltReason': 'Halt Reason',
'expiryNotice': 'Expiry Notice',
'nearExpiryNotice': 'Near-Expiry Notice',
'daysRemaining': '{days} days remaining',
'daysExpired': '{days} days after expiry',
'soldAfterExpiry': 'Sold after expiry',
'expiringSoon': 'Expiring Soon',
'expiryReport': 'Expiry Report',
// ... add more as needed
```

---

## Phase 3 Tasks — Reports + Alerts

### Task 3.3: Expiry Report Screen (NEW)
**File:** `lib/features/reports/expiry_report_screen.dart` (create new)

A PlutoGrid-based report screen with:
1. **Filters bar** at top:
   - Warehouse selector (dropdown)
   - Status filter: All / Expired / Near-Expiry / Normal
   - Threshold days override (number input)
   - Category filter
2. **PlutoGrid** with columns: Item Code, Item Name, Batch No, Warehouse, Qty Remaining, Unit Cost, Total Value, Received Date, Expiry Date (color-coded), Status (badge), Days Until Expiry, Halted
3. **CSV export** button (use existing `saveCsv()` helper)
4. **Color coding:** Red rows for expired, orange for near-expiry, green for normal

API: `GET /api/reports/expiry?warehouse_id=&threshold_days=&status=`

### Task 3.4: Dashboard Expiry Widget
**File:** `lib/features/dashboard/` (add new widget file)

A dashboard card: **"Expiring Soon"**
- Shows top 5–10 batches expiring within configurable threshold
- Each row: Item name, batch no, expiry date, days remaining, warehouse
- Color-coded: red if expired, yellow if near-expiry
- Click navigates to batch management screen for that item
- Uses `GET /api/dashboard/expiry-alerts?days=30`

Add this widget to the existing dashboard layout.

### Task 3.5: Batch Traceability Report — Add Expiry Columns
**File:** `lib/features/reports/batch_traceability_report_screen.dart`, `lib/data/models/report.dart`

Add `Expiry Date` and `Status` columns to the existing batch traceability grid.

### Task 3.6: Report Providers
**File:** `lib/features/reports/report_providers.dart`

Add Riverpod providers:
```dart
final expiryReportProvider = FutureProvider.autoDispose<List<ExpiryReportRow>>((ref) async { ... });
final expiryAlertsProvider = FutureProvider.autoDispose<List<ExpiryAlert>>((ref) async { ... });
```

### Tasks 3.7: Localization for Reports
Add strings for expiry report, dashboard widget, etc.

---

## Important Notes

1. **Follow existing patterns** — Look at how similar screens/forms are built and match their style exactly.
2. **All strings must be localized** — No hardcoded English strings in widgets. Use `AppLocalizations.of(context)!`.
3. **Error handling** — All API calls must handle errors with `try/catch` and show `showAppToast()` on failure.
4. **Loading states** — Show `CircularProgressIndicator` while data loads.
5. **Mobile layout** — The spec says mobile uses compact card system. Ensure batch management works on mobile too.
6. **Don't touch server files** — Phase 1 (server) is being done by another agent. Only modify Flutter/Dart files.
7. **Run `flutter analyze`** before considering your work done — zero errors required.
8. **Test on both platforms** if possible — Desktop (PlutoGrid) and mobile (compact cards).

## Files You Should NOT Modify
- `server/` — All server-side files are off-limits
- `lib/data/models/batch.dart` — Doesn't exist, you'll create `stock_batch.dart` instead

## Deliverables
- All Phase 2 files modified/created
- All Phase 3 files modified/created
- `flutter analyze` passes with zero errors
- All localization strings added (en + ur)
