// Shared A4 PDF printing — PORTING.md §12. Every A4 print action
// (invoice form, quotation form + detail dialog, sales order form +
// detail dialog) builds its PDF bytes with the `pdf` package and then
// shows the native print dialog with `printing`. That final step is
// identical at all call sites, so it lives here instead of being copied
// five times.

import 'dart:typed_data';

import 'package:flutter/widgets.dart' show BuildContext;
import 'package:printing/printing.dart';

/// Shows the native print dialog for pre-built PDF [bytes], falling back
/// to the share/save-as-PDF sheet when the platform has no print backend
/// (e.g. some Linux setups). A share failure propagates to the caller's
/// own error handling (the handlers wrap the whole fetch/build/print
/// step in a try/catch that toasts). Bails out silently if the widget is
/// unmounted while the layout dialog is open.
Future<void> printPdfBytes(
  Uint8List bytes,
  String filename,
  BuildContext context,
) async {
  try {
    await Printing.layoutPdf(onLayout: (format) async => bytes);
  } catch (_) {
    if (!context.mounted) return;
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }
}
