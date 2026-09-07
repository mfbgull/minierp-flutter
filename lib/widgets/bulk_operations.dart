// Bulk-operation plumbing shared by every PlutoGrid screen with bulk
// actions (spec.md "Extend Bulk Operations" — Phase 0 alignment).
//
// - [runBulkOperation] executes one API call per selected id, serially
//   (D22: the server's `sensitiveOperationLimiter` allows 10 delete
//   calls/min on several routes; parallelism would 429 mid-batch). A 429
//   response waits `retryAfter` seconds and retries the record once; a
//   second 429 lands in the failure list ("rate limited"). The operation
//   never aborts the whole batch because of the limiter.
// - [BulkFailure] / [showBulkFailureDialog] render the D11 partial-
//   failure dialog: succeeded count at top, a scrollable per-record list
//   of `<label>: <server reason>`.
// - [BulkActionBar.busy] (D13): while an operation is in flight the bar
//   disables its actions and shows a spinner — selection is preserved
//   and a second operation cannot start.

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repositories/api_result.dart';
import '../l10n/app_localizations.dart';
import 'app_toast.dart';
import 'movable_dialog.dart';
import 'pluto_grid_screen.dart' show GridBulkSelection;

/// Pacing knobs for [runBulkOperation] — injectable so widget tests can
/// zero the waits (fake-async pumping is flaky across real timers).
class BulkPacing {
  /// Small serial pause between calls (D22) — keeps the limiter honest
  /// without turning a bulk into a crawl.
  static Duration interCallDelay = const Duration(milliseconds: 150);

  /// The bounded limiter window the executor waits out on a 429 before
  /// the single retry.
  static Duration maxRetryDelay = const Duration(seconds: 65);

  /// Tests call this (via addTearDown restore) to remove real-time waits.
  static void disableForTests() {
    interCallDelay = Duration.zero;
    maxRetryDelay = Duration.zero;
  }
}

/// One failed record in a bulk operation — the row's display label plus
/// the server's rejection reason (D11: the dialog lists every failure,
/// one line per record).
class BulkFailure {
  const BulkFailure({required this.label, required this.reason});

  /// Human-readable record label (e.g. `INV-2026-440956`, `Widget A`).
  final String label;

  /// The server's message for this record (or the transport message).
  final String reason;
}

/// The result of [runBulkOperation]: the ids that succeeded, in call
/// order (the undo flow replays exactly these), and one [BulkFailure]
/// per rejected id.
class BulkOperationResult {
  const BulkOperationResult({required this.succeeded, required this.failures});

  /// Selected ids whose call returned success — order preserved.
  final List<int> succeeded;

  /// One entry per failed id, with the record label and server reason.
  final List<BulkFailure> failures;

  bool get allSucceeded => failures.isEmpty;
  bool get anySucceeded => succeeded.isNotEmpty;
  int get okCount => succeeded.length;
  int get failedCount => failures.length;
}

/// Executes [operation] for every id in [ids], one call at a time (D22).
///
/// [labelFor] turns a record id into the display label used by the
/// failure dialog and by [onProgress]'s spinner text.
///
/// 429 handling: the server's limiter body is
/// `{error: 'Too many requests…', retryAfter: 60}`. On a 429 the executor
/// waits `retryAfter` seconds (capped to [maxRetryDelay] so a broken
/// server value cannot hang the UI) and retries the same record once; a
/// second 429 (or any other failure) is recorded as a [BulkFailure].
/// In tests the wait is simulated via [delay] — the default pumps real
/// time with [Future.delayed], tests inject a no-op.
Future<BulkOperationResult> runBulkOperation({
  required List<int> ids,
  required String Function(int id) labelFor,
  required Future<ApiResult<void>> Function(int id) operation,
  void Function(int done, int total, String label)? onProgress,
  Duration? interCallDelay,
  Duration? maxRetryDelay,
  Future<void> Function(Duration)? delay = Future.delayed,
}) async {
  final pauseBetween = interCallDelay ?? BulkPacing.interCallDelay;
  final retryWindow = maxRetryDelay ?? BulkPacing.maxRetryDelay;
  final succeeded = <int>[];
  final failures = <BulkFailure>[];

  var done = 0;
  for (final id in ids) {
    onProgress?.call(done, ids.length, labelFor(id));

    var result = await operation(id);
    if (_isRateLimited(result)) {
      // Rate limited — wait out the limiter window (bounded) and retry
      // the record once. A second 429 becomes a per-record failure. The
      // server sends `retryAfter` seconds in the body; the transport
      // layer reduces it to a message, so use the bounded window.
      await delay?.call(retryWindow);
      result = await operation(id);
    }

    result.fold(
      onSuccess: (_) => succeeded.add(id),
      onFailure: (error) =>
          failures.add(BulkFailure(label: labelFor(id), reason: error.message)),
    );
    done++;
    if (done < ids.length && pauseBetween > Duration.zero) {
      await delay?.call(pauseBetween);
    }
  }

  return BulkOperationResult(succeeded: succeeded, failures: failures);
}

/// A 429 response (the server's `sensitiveOperationLimiter`) — the
/// executor's retry trigger (D22).
bool _isRateLimited(ApiResult<void> result) =>
    result.fold(onSuccess: (_) => false, onFailure: (e) => e.statusCode == 429);

/// The D11 partial-failure dialog: succeeded count on top, then a
/// scrollable list of `<label>: <reason>` lines (one per failed record).
/// Returns when the user closes it; no return value (the caller has
/// already applied the outcome).
Future<void> showBulkFailureDialog(
  BuildContext context, {
  required int succeededCount,
  required List<BulkFailure> failures,
}) {
  final l10n = AppLocalizations.of(context)!;
  final scheme = Theme.of(context).colorScheme;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => MovableDialog(
      key: const Key('bulk_failure_dialog'),
      dialogId: 'bulk-failures',
      maxWidth: 520,
      showHandle: false,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_outlined,
                    size: 22, color: scheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.bulkPartialFailureTitle(
                      succeededCount,
                      failures.length,
                    ),
                    style: Theme.of(dialogContext).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final failure in failures)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: failure.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(
                                text: ': ${failure.reason}',
                                style: TextStyle(color: scheme.error),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.commonClose),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The outcome flow every bulk handler ends with (spec "Edge Cases" 1–3):
/// - all succeeded → success toast (with the optional 10s Undo action);
/// - mixed → the D11 failure dialog (plus the Undo toast when some
///   deletes succeeded — Undo restores only the succeeded ids);
/// - everything failed → error toast (nothing changed, no dialog noise).
/// Clears [bulk] afterwards and lets the screen refresh its provider via
/// [onComplete] (which runs in both success and failure paths — the grid
/// must reflect whatever the server accepted).
Future<void> finishBulkOperation(
  BuildContext context, {
  required GridBulkSelection bulk,
  required BulkOperationResult result,
  required String Function(int count) successMessage,
  String Function(int count)? undoMessage,
  VoidCallback? onUndo,
  VoidCallback? onComplete,
}) async {
  final l10n = AppLocalizations.of(context)!;

  if (result.allSucceeded) {
    if (onUndo != null && undoMessage != null) {
      showAppToast(
        context,
        successMessage(result.okCount),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(label: l10n.commonUndo, onPressed: onUndo),
      );
    } else {
      showAppToast(context, successMessage(result.okCount));
    }
  } else if (result.anySucceeded) {
    await showBulkFailureDialog(
      context,
      succeededCount: result.okCount,
      failures: result.failures,
    );
    // Partial success on a destructive op still offers the undo window
    // over the records that DID change (D11 edge case 2).
    if (context.mounted && onUndo != null && undoMessage != null) {
      showAppToast(
        context,
        undoMessage(result.okCount),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(label: l10n.commonUndo, onPressed: onUndo),
      );
    }
  } else {
    showAppToast(
      context,
      result.failures.first.reason,
      isError: true,
    );
  }

  bulk.clear();
  onComplete?.call();
}
