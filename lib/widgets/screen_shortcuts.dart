// Screen-level keyboard shortcuts for the list screens — Ctrl+F focuses
// the toolbar search field, Ctrl+N triggers the screen's primary "New …"
// action, Ctrl+R re-runs the screen's refresh, and Ctrl+E fires the
// CSV-export action (PORTING.md power-user niceties).
//
// Every list screen renders the shared `ScreenToolbar` row, so instead of
// registering bindings per screen (40+ call sites) the AppShell wraps its
// body in [ScreenShortcutScope] and the key handler resolves the target
// at *keypress time* by walking this scope's element subtree:
//
//   - go_router's StatefulShellRoute.indexedStack keeps every branch's
//     screen mounted and marks the hidden ones with
//     `TickerMode(enabled: false)` (see `_IndexedStackedRouteBranchContainer`
//     in go_router 17.x), so a disabled [TickerMode] prunes a whole branch
//     from the walk — only the visible branch's toolbar can be found;
//   - within the visible branch, only the toolbar of the *current* route
//     responds (`ModalRoute.isCurrent`), so a detail page pushed over a
//     list doesn't trigger the list's shortcuts underneath.
//
// Why a [HardwareKeyboard] handler instead of [Shortcuts] bindings:
// PlutoGrid's FocusScope.onKeyEvent returns `KeyEventResult.handled` for
// *every* key while a cell holds focus (pluto_grid 8.x
// `_handleGridFocusOnKey`), and in Flutter 3.4x a `Shortcuts` widget
// dispatches through its own inner `Focus(onKeyEvent:)` — so an outer
// CallbackShortcuts never sees the chords when the grid is focused
// (verified empirically + in framework source). HardwareKeyboard handlers
// run *before* the focus system, so the scope sees the keys first no
// matter where focus sits. The dialog gate below keeps the shortcuts
// inert while a modal is open.
//
// Resolving from the live tree means there is no registry to keep in sync
// across branch switches, rebuilds or tests.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        HardwareKeyboard,
        KeyDownEvent,
        KeyEvent,
        KeyRepeatEvent,
        LogicalKeyboardKey;

import 'screen_toolbar.dart' show ScreenToolbarState;

/// Dispatches Ctrl+F / Ctrl+N / Ctrl+R / Ctrl+E to the toolbar of the
/// visible shell branch.
class ScreenShortcutScope extends StatefulWidget {
  const ScreenShortcutScope({super.key, required this.child});

  final Widget child;

  @override
  State<ScreenShortcutScope> createState() => _ScreenShortcutScopeState();
}

class _ScreenShortcutScopeState extends State<ScreenShortcutScope> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    super.dispose();
  }

  /// Ctrl+F / Ctrl+N / Ctrl+R / Ctrl+E from anywhere inside the shell.
  /// Returns true only for a consumed chord keydown so the event stops
  /// before the focused widget (e.g. a PlutoGrid) can swallow or
  /// re-purpose it.
  bool _onKeyEvent(KeyEvent event) {
    // Auto-repeat keeps firing KeyRepeatEvent — act once per press. Only
    // the bare Ctrl+F / Ctrl+N / Ctrl+R / Ctrl+E chord (no shift/alt/meta)
    // is a shortcut.
    final keyboard = HardwareKeyboard.instance;
    if (event is! KeyDownEvent ||
        event is KeyRepeatEvent ||
        !keyboard.isControlPressed ||
        keyboard.isShiftPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return false;
    }
    final logical = event.logicalKey;
    if (logical != LogicalKeyboardKey.keyF &&
        logical != LogicalKeyboardKey.keyN &&
        logical != LogicalKeyboardKey.keyR &&
        logical != LogicalKeyboardKey.keyE) {
      return false;
    }
    // A modal dialog's focus is outside this scope — its keys must pass
    // through untouched. (Nothing focused at all means no modal can be
    // open, so the visible screen may still respond.)
    if (!_focusInsideScope()) return false;
    final toolbar = _visibleToolbar();
    if (logical == LogicalKeyboardKey.keyF) {
      toolbar?.focusSearch();
    } else if (logical == LogicalKeyboardKey.keyN) {
      toolbar?.triggerNew();
    } else if (logical == LogicalKeyboardKey.keyR) {
      toolbar?.triggerRefresh();
    } else if (logical == LogicalKeyboardKey.keyE) {
      toolbar?.triggerExport();
    }
    return true;
  }

  /// Whether the primary focus lives inside this scope (i.e. a shell
  /// screen, not a dialog/modal pushed on top of it).
  bool _focusInsideScope() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return true;
    return context.findAncestorStateOfType<_ScreenShortcutScopeState>() != null;
  }

  /// The toolbar of the currently visible screen — resolved from the live
  /// element tree at keypress time, so there is no registry to keep in
  /// sync (the shell keeps hidden branches mounted and ticking).
  ScreenToolbarState? _visibleToolbar() {
    ScreenToolbarState? found;
    // The scope's own element is never a toolbar, so start below it.
    context.visitChildElements((child) {
      found ??= _findVisibleToolbar(child);
    });
    return found;
  }

  ScreenToolbarState? _findVisibleToolbar(Element element) {
    // Hidden shell branch (go_router wraps each branch in
    // TickerMode(enabled: isActive)) — prune the whole subtree so a
    // hidden screen's toolbar can never respond.
    if (element.widget is TickerMode &&
        !(element.widget as TickerMode).enabled) {
      return null;
    }
    if (element is StatefulElement && element.state is ScreenToolbarState) {
      final toolbar = element.state as ScreenToolbarState;
      // Covered sub-routes (a detail page over its list) keep their
      // toolbars mounted; only the current route's one responds.
      final route = ModalRoute.of(element);
      if (route == null || route.isCurrent) return toolbar;
    }
    ScreenToolbarState? found;
    element.visitChildren((child) {
      found ??= _findVisibleToolbar(child);
    });
    return found;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
