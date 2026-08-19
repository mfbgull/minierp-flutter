// Activity log detail dialog — opened by F2/Enter/double-tap on a row in
// the activity grid. The list row already carries every field (the server
// joins the username), so unlike the customer/item dialogs there is no
// per-id fetch: the row is passed straight through.
//
// Layout mirrors the other detail dialogs (DetailInfoRows label/value
// grid + DetailTiles): a header with the action + level badge, the
// description as the hero line, then the technical fields.

import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/activity_log.dart' show ActivityLog;
import '../../l10n/app_localizations.dart';
import '../../widgets/detail_labels.dart';
import '../../widgets/detail_rows.dart';
import '../../widgets/status_badge.dart';
import 'activity_log_presenters.dart';

/// Opens the read-only detail dialog for [log].
Future<void> showActivityLogDetailDialog(
  BuildContext context, {
  required ActivityLog log,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _ActivityLogDetailDialog(log: log),
  );
}

class _ActivityLogDetailDialog extends StatelessWidget {
  const _ActivityLogDetailDialog({required this.log});

  final ActivityLog log;

  static String _duration(int? ms) =>
      ms == null ? '—' : '${Formatters.number(ms)} ms';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.activitylogDetailtitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  StatusBadge(
                    status: log.logLevel,
                    color: activityLogLevelColor(scheme, log.logLevel),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Hero line — inside the scroll area so a very long
                      // description scrolls instead of overflowing the
                      // dialog's fixed height.
                      Text(
                        log.description.isEmpty
                            ? detailDash(null)
                            : log.description,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 16),
                      DetailInfoRows(
                        rows: [
                          (l10n.activitylogUser, detailDash(log.username)),
                          (l10n.activitylogAction, log.action),
                          (l10n.activitylogEntity, log.entityLabel),
                          (
                            l10n.activitylogTimestamp,
                            formatActivityTimestamp(log.createdAt),
                          ),
                          (l10n.activitylogLevel, log.logLevel),
                          (l10n.activitylogIp, detailDash(log.ipAddress)),
                          (
                            l10n.activitylogUseragent,
                            detailDash(log.userAgent),
                          ),
                          (l10n.activitylogDuration, _duration(log.durationMs)),
                          if (log.metadata != null)
                            (l10n.activitylogMetadata, log.metadata!),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.commonClose),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
