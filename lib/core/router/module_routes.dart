import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/shell/deferred_branch.dart' show DeferredBranch;
import 'shell_destination.dart';

export 'shell_destination.dart' show ShellDestination;

/// Per-module route definition (SHORTCOMINGS-FIX 1.1). Each feature
/// implements this in its own `*_routes.dart` file; `module_registry.dart`
/// collects them so `app.dart` never imports feature screens directly.
abstract class ModuleRoutes {
  const ModuleRoutes();

  /// Rail/shell destination. Null for modules that only contribute
  /// standalone routes (e.g. auth's splash/login/change-password).
  ShellDestination? get destination;

  /// GoRoutes hosted inside the authenticated shell branch: the root
  /// screen (wrapped in [DeferredBranch], spec 7.1) plus sub-routes.
  List<GoRoute> get branchRoutes => const [];

  /// Standalone GoRoutes outside the shell (auth screens, full-page
  /// forms, print previews).
  List<GoRoute> get standaloneRoutes => const [];
}

/// Builds a shell branch's root GoRoute: the module screen wrapped in
/// [DeferredBranch] so the branch only materializes (and fetches) on
/// first visit.
GoRoute branchRoute({
  required ShellDestination destination,
  required WidgetBuilder builder,
  List<GoRoute> subRoutes = const [],
}) => GoRoute(
  path: destination.path,
  builder: (context, state) => DeferredBranch(
    path: destination.path,
    builder: builder,
  ),
  routes: subRoutes,
);