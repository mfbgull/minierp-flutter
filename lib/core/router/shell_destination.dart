import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// One module in the shell's navigation. [label] is resolved with the
/// active localization; [path] is the router branch root; [adminOnly]
/// destinations are hidden for non-admin users.
class ShellDestination {
  const ShellDestination({
    required this.path,
    required this.label,
    required this.icon,
    this.adminOnly = false,
    this.title,
    this.hideInRail = false,
  });

  final String path;
  final String Function(AppLocalizations) label;
  final IconData icon;
  final bool adminOnly;

  /// App-bar title; defaults to [label] so modules whose rail label is
  /// branded differently (e.g. "Manufacturing" vs "Production") can keep
  /// the feature name in the app bar.
  final String Function(AppLocalizations)? title;

  /// When true the module stays reachable (its router branch is still
  /// built from [shellDestinations]) but is omitted from the sidebar
  /// rail — e.g. Settings, which lives in the top app bar instead.
  final bool hideInRail;
}