// Ledger grouping — pure port of `utils/ledgerGrouping.ts` (web client).
// Groups AR ledger entries by invoice so the customer detail Ledger tab
// can render expandable invoice groups (group header = the invoice
// entry; children = the payments/cancellations against it), with the
// web's exact rules: RETURN entries are never grouped, an entry's invoice
// is resolved via `linked_invoice_no` first, then its own reference when
// the type is INVOICE/CANCELLATION, then a `for/against/on INV-…`
// description match. Entries that resolve to nothing become ungrouped
// rows.

import '../../../data/models/ledger_entry.dart' show LedgerEntry;

/// One invoice group: the invoice entry itself plus its linked entries.
class InvoiceGroup {
  InvoiceGroup({
    required this.invoice,
    required this.children,
    required this.totalPaid,
    required this.balance,
  });

  final LedgerEntry invoice;
  final List<LedgerEntry> children;

  /// Sum of the linked PAYMENT entries' credits (mutated while grouping).
  num totalPaid;

  /// `invoice.debit - totalPaid` (the invoice's remaining balance;
  /// mutated while grouping).
  num balance;
}

/// An entry that could not be attributed to any invoice (RETURN/REFUND
/// entries and payments whose description has no invoice reference).
class UngroupedEntry {
  const UngroupedEntry({required this.entry});

  final LedgerEntry entry;
}

/// A node of the grouped ledger: either an invoice group or a lone
/// ungrouped entry, in original ledger order (web `LedgerGroupNode`).
sealed class LedgerGroupNode {
  const LedgerGroupNode();
}

class InvoiceGroupNode extends LedgerGroupNode {
  const InvoiceGroupNode(this.group);

  final InvoiceGroup group;
}

class UngroupedNode extends LedgerGroupNode {
  const UngroupedNode(this.entry);

  final UngroupedEntry entry;
}

/// Resolves which invoice an entry belongs to — the web
/// `extractInvoiceNo`: RETURN entries never resolve; `linked_invoice_no`
/// wins when present; INVOICE/CANCELLATION entries group by their own
/// reference; otherwise a `for|against|on INV-…` description match.
String? extractInvoiceNo(LedgerEntry entry) {
  if (entry.transactionType == 'RETURN') return null;
  if (entry.linkedInvoiceNo?.isNotEmpty ?? false) {
    return entry.linkedInvoiceNo;
  }
  if (entry.transactionType == 'INVOICE' ||
      entry.transactionType == 'CANCELLATION') {
    return entry.referenceNo;
  }
  final match = RegExp(
    r'(?:for|against|on)\s+(INV-[\w-]+)',
    caseSensitive: false,
  ).firstMatch(entry.description);
  return match?.group(1);
}

/// Groups [ledger] by invoice (web `groupLedgerByInvoice`), preserving
/// the ledger's display order: each INVOICE entry becomes its group's
/// header; every other entry is either attached to its resolved group or
/// emitted as an ungrouped node.
List<LedgerGroupNode> groupLedgerByInvoice(List<LedgerEntry> ledger) {
  final invoiceMap = <String, InvoiceGroup>{};
  for (final inv in ledger) {
    if (inv.transactionType != 'INVOICE') continue;
    invoiceMap[inv.referenceNo] = InvoiceGroup(
      invoice: inv,
      children: [],
      totalPaid: 0,
      balance: inv.debit,
    );
  }

  final ungrouped = <UngroupedEntry>[];
  for (final entry in ledger) {
    if (entry.transactionType == 'INVOICE') continue;
    final invoiceNo = extractInvoiceNo(entry);
    final group = invoiceNo == null ? null : invoiceMap[invoiceNo];
    if (group != null) {
      group.children.add(entry);
      if (entry.transactionType == 'PAYMENT') {
        group.totalPaid += entry.credit;
      }
      group.balance = group.invoice.debit - group.totalPaid;
    } else {
      ungrouped.add(UngroupedEntry(entry: entry));
    }
  }

  final result = <LedgerGroupNode>[];
  for (final entry in ledger) {
    if (entry.transactionType == 'INVOICE') {
      final group = invoiceMap[entry.referenceNo];
      if (group != null) result.add(InvoiceGroupNode(group));
    } else {
      for (final ug in ungrouped) {
        if (ug.entry.id == entry.id) {
          result.add(UngroupedNode(ug));
          break;
        }
      }
    }
  }
  return result;
}
