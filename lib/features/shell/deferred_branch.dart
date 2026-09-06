import 'package:flutter/widgets.dart';

/// Tells every [DeferredBranch] host which shell branch is currently
/// shown, so the hosts can materialize on first visit (spec 7.1).
/// Provided by [AppShell] around the `StatefulShellRoute`'s navigator;
/// go_router re-invokes the shell builder on branch changes, so this
/// always carries the freshly updated current branch path.
class BranchVisibility extends InheritedWidget {
  const BranchVisibility({
    super.key,
    required this.currentPath,
    required super.child,
  });

  /// Router path of the branch currently visible in the shell.
  final String currentPath;

  static BranchVisibility? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BranchVisibility>();

  @override
  bool updateShouldNotify(BranchVisibility oldWidget) =>
      oldWidget.currentPath != currentPath;
}

/// Lazily materializes a shell branch's root screen (spec 7.1).
///
/// `StatefulShellRoute.indexedStack` builds every branch eagerly, so
/// without this every module's providers would fire their fetches at
/// login (15+ parallel calls). The host renders an empty box until its
/// own [path] becomes the current branch; the real screen then mounts
/// and its providers fetch. After the first visit the screen stays
/// mounted — the IndexedStack preserves its state across switches, and
/// `module_refresh.dart` handles refresh-on-revisit.
class DeferredBranch extends StatefulWidget {
  const DeferredBranch({super.key, required this.path, required this.builder});

  /// The branch's router root path (a `shellDestinations` path).
  final String path;

  /// Builds the branch's root screen once the branch is first visited.
  final WidgetBuilder builder;

  @override
  State<DeferredBranch> createState() => _DeferredBranchState();
}

class _DeferredBranchState extends State<DeferredBranch> {
  bool _visited = false;

  @override
  Widget build(BuildContext context) {
    final visibility = BranchVisibility.maybeOf(context);
    if (visibility?.currentPath == widget.path) {
      _visited = true;
    }
    if (!_visited) return const SizedBox.shrink();
    return widget.builder(context);
  }
}