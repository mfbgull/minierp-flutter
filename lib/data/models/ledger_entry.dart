import 'json_helpers.dart';

/// Port of `LedgerEntry` (types/client-types.ts) — a row of the
/// customer AR ledger (`GET /customers/:id/ledger`, backed by the
/// `customer_ledger` table). Consumed by the customer balance/credit
/// calculations (`features/customers/calculations/`).
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.transactionDate,
    required this.transactionType,
    required this.referenceNo,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
    this.linkedInvoiceNo,
  });

  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
    id: asInt(json['id']) ?? 0,
    transactionDate: asString(json['transaction_date']) ?? '',
    transactionType: asString(json['transaction_type']) ?? '',
    referenceNo: asString(json['reference_no']) ?? '',
    description: asString(json['description']) ?? '',
    debit: asNum(json['debit']) ?? 0,
    credit: asNum(json['credit']) ?? 0,
    balance: asNum(json['balance']) ?? 0,
    linkedInvoiceNo: asString(json['linked_invoice_no']),
  );

  final int id;
  final String transactionDate;
  final String transactionType; // INVOICE, PAYMENT, RETURN, REFUND, ADJUSTMENT…
  final String referenceNo;
  final String description;
  final num debit;
  final num credit;
  final num balance;
  final String? linkedInvoiceNo;

  Map<String, dynamic> toJson() => {
    'id': id,
    'transaction_date': transactionDate,
    'transaction_type': transactionType,
    'reference_no': referenceNo,
    'description': description,
    'debit': debit,
    'credit': credit,
    'balance': balance,
    if (linkedInvoiceNo != null) 'linked_invoice_no': linkedInvoiceNo,
  };
}
