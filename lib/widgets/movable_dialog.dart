import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/app_motion.dart';
import 'dialog_geometry.dart';

/// Key for the drag handle — also used by widget tests to drag the dialog.
const Key kMovableDialogHandleKey = Key('movable_dialog_handle');

/// A dialog wrapper that adds a drag handle so the user can reposition
/// the dialog by dragging the header area. Position is persisted across
/// sessions using [SharedPreferences] keyed by [dialogId].
///
/// The dialog is clamped inside the viewport on restore, drag and window
/// resize, and snaps to a nearby edge with a short animation. Escape
/// closes it by default.
class MovableDialog extends StatefulWidget {
  const MovableDialog({
    super.key,
    required this.child,
    this.dialogId,
    this.title,
    this.maxWidth = 500,
    this.maxHeight = 480,
    this.showHandle = true,
    this.snapThreshold = 40.0,
    this.enableKeyboardShortcuts = true,
    this.enableEscapeKey = true,
    this.autofocusEscape = false,
    this.keyboardStep = 30.0,
  });

  /// Unique key used to persist/restore the dialog position.
  /// When null, position is not persisted.
  final String? dialogId;

  final Widget child;
  final String? title;
  final double maxWidth;
  final double maxHeight;
  final bool showHandle;

  /// Distance in pixels from a screen edge that triggers snapping.
  final double snapThreshold;

  /// Whether Ctrl+Arrow keys can move the dialog.
  final bool enableKeyboardShortcuts;

  final bool enableEscapeKey;

  /// Gives the dialog's escape focus node the initial focus. Used by
  /// dialogs that manage their own tab order and have no autofocus field.
  /// Leave false when the content autofocuses a field.
  final bool autofocusEscape;

  /// Pixels to move per Ctrl+Arrow press.
  final double keyboardStep;

  @override
  State<MovableDialog> createState() => _MovableDialogState();
}

class _MovableDialogState extends State<MovableDialog>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final ValueNotifier<Offset> _offset = ValueNotifier(Offset.zero);
  final GlobalKey _dialogKey = GlobalKey();
  late final FocusNode _focusNode;
  late final FocusNode _escapeFocusNode;

  late final AnimationController _snapController;
  Animation<Offset>? _snapAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
    _focusNode = FocusNode();
    _escapeFocusNode = FocusNode(debugLabel: 'movable_dialog_escape');
    _snapController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 180),
        )..addListener(() {
          final animation = _snapAnimation;
          if (animation != null) _offset.value = animation.value;
        });
    _loadPosition();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _clampToViewport();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    _focusNode.dispose();
    _escapeFocusNode.dispose();
    _snapController.dispose();
    _offset.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _clampToViewport();
    });
  }

  String get _prefsKey => 'movable_dialog_${widget.dialogId}';

  Size? get _dialogSize {
    final render = _dialogKey.currentContext?.findRenderObject();
    if (render is RenderBox && render.hasSize) return render.size;
    return null;
  }

  Future<void> _loadPosition() async {
    if (widget.dialogId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final x = prefs.getDouble('${_prefsKey}_x');
      final y = prefs.getDouble('${_prefsKey}_y');
      if (x != null && y != null && mounted) {
        _offset.value = Offset(x, y);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _clampToViewport();
        });
      }
    } on Exception {
      // Position memory is optional; a missing store keeps the dialog
      // centered.
    }
  }

  Future<void> _savePosition() async {
    if (widget.dialogId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('${_prefsKey}_x', _offset.value.dx);
      await prefs.setDouble('${_prefsKey}_y', _offset.value.dy);
    } on Exception {
      // Position memory is best-effort.
    }
  }

  void _clampToViewport() {
    if (!mounted) return;
    final size = _dialogSize;
    if (size == null) return;
    _offset.value = clampDialogOffset(
      offset: _offset.value,
      dialogSize: size,
      screenSize: MediaQuery.sizeOf(context),
    );
  }

  /// Escape works even when the dialog has not placed focus on a control
  /// (for example, a dialog opened from a keyboard shortcut). It only
  /// claims the key when the focused node is the dialog route's scope or
  /// nothing at all — a focused field or an open popup handles Escape
  /// itself first.
  bool _handleGlobalKey(KeyEvent event) {
    if (!widget.enableEscapeKey) return false;
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }

    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;

    final primary = FocusManager.instance.primaryFocus;
    final scope = FocusScope.of(context);
    if (primary != null && !identical(primary, scope)) return false;

    unawaited(Navigator.of(context).maybePop());
    return true;
  }

  /// Snap to the nearest edge when the rendered dialog is close to one.
  void _snapToEdge() {
    if (!mounted) return;
    final size = _dialogSize;
    if (size == null) {
      unawaited(_savePosition());
      return;
    }

    final target = snapDialogOffset(
      offset: _offset.value,
      dialogSize: size,
      screenSize: MediaQuery.sizeOf(context),
      threshold: widget.snapThreshold,
    );
    if (target == null || target == _offset.value) {
      unawaited(_savePosition());
      return;
    }

    final duration = AppMotion.duration(
      context,
      const Duration(milliseconds: 180),
    );
    if (duration == Duration.zero) {
      _offset.value = target;
      unawaited(_savePosition());
      return;
    }

    _snapAnimation = Tween<Offset>(begin: _offset.value, end: target).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic),
    );
    _snapController.forward(from: 0).then((_) {
      if (!mounted) return;
      _offset.value = target;
      _snapAnimation = null;
      unawaited(_savePosition());
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _offset.value = _offset.value + details.delta;
  }

  /// Handle Ctrl+Arrow keyboard shortcuts to move the dialog.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (!widget.enableKeyboardShortcuts) return KeyEventResult.ignored;

    final isCtrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (!isCtrl) return KeyEventResult.ignored;

    final step = widget.keyboardStep;
    Offset delta;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        delta = Offset(-step, 0);
      case LogicalKeyboardKey.arrowRight:
        delta = Offset(step, 0);
      case LogicalKeyboardKey.arrowUp:
        delta = Offset(0, -step);
      case LogicalKeyboardKey.arrowDown:
        delta = Offset(0, step);
      default:
        return KeyEventResult.ignored;
    }

    _offset.value = _offset.value + delta;
    _snapToEdge();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: widget.enableEscapeKey
          ? {
              const SingleActivator(LogicalKeyboardKey.escape): () {
                unawaited(Navigator.of(context).maybePop());
              },
            }
          : const {},
      child: Focus(
        focusNode: _escapeFocusNode,
        autofocus: widget.autofocusEscape,
        child: Focus(
          focusNode: _focusNode,
          onKeyEvent: _handleKeyEvent,
          canRequestFocus: false,
          child: ValueListenableBuilder<Offset>(
            valueListenable: _offset,
            child: Dialog(
              child: ConstrainedBox(
                key: _dialogKey,
                constraints: BoxConstraints(
                  maxWidth: widget.maxWidth,
                  maxHeight: widget.maxHeight,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.showHandle)
                      GestureDetector(
                        key: kMovableDialogHandleKey,
                        onPanUpdate: _onPanUpdate,
                        onPanEnd: (_) => _snapToEdge(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Theme.of(
                                  context,
                                ).dividerColor.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 32,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (widget.title != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: Semantics(
                          header: true,
                          namesRoute: true,
                          child: Text(
                            widget.title!,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ),
                    Flexible(child: widget.child),
                  ],
                ),
              ),
            ),
            builder: (context, offset, child) =>
                Transform.translate(offset: offset, child: child),
          ),
        ),
      ),
    );
  }
}
