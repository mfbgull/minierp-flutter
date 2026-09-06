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
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.inverseSurface,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        action: action,
      ),
    );
}