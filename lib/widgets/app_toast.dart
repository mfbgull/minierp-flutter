import 'package:flutter/material.dart';

/// SnackBar helper — success/error feedback (PORTING.md §9: toasts for
/// errors, no silent failures).
///
/// [action] and [duration] support the undo flow (SHORTCOMINGS-FIX 4.2):
/// destructive operations pass an Undo action and a longer (10s) window
/// so the user can revert the delete.
void showAppToast(
  BuildContext context,
  String message, {
  bool isError = false,
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 3),
}) {
  final messenger = ScaffoldMessenger.of(context);
  final scheme = Theme.of(context).colorScheme;
  final effectiveAction = action == null
      ? null
      : isError
      ? SnackBarAction(
          label: action.label,
          onPressed: action.onPressed,
          textColor: scheme.onError,
          disabledTextColor: scheme.onError.withValues(alpha: 0.5),
        )
      : action;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: isError ? TextStyle(color: scheme.onError) : null,
        ),
        backgroundColor: isError ? scheme.error : scheme.inverseSurface,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        action: effectiveAction,
      ),
    );
}
