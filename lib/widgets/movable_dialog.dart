import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A dialog wrapper that adds a drag handle so the user can reposition
/// the dialog by dragging the header area. Position is persisted across
/// sessions using [SharedPreferences] keyed by [dialogId].
///
/// When dragged near a screen edge, the dialog snaps to that edge with
/// a smooth animation.
///
/// Usage:
/// ```dart
/// showDialog(
///   context: context,
///   builder: (_) => MovableDialog(
///     dialogId: 'employee_detail',
///     child: Column(children: [ ... ]),
///   ),
/// );
/// ```
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

  /// Pixels to move per Ctrl+Arrow press.
  final double keyboardStep;

  @override
  State<MovableDialog> createState() => _MovableDialogState();
}

class _MovableDialogState extends State<MovableDialog>
    with SingleTickerProviderStateMixin {
  Offset _offset = Offset.zero;
  late final FocusNode _focusNode;

  late final AnimationController _snapController;
  Animation<Offset>? _snapAnimation;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(() {
        if (_snapAnimation != null) {
          setState(() {
            _offset = _snapAnimation!.value;
          });
        }
      });
    _loadPosition();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _snapController.dispose();
    super.dispose();
  }

  String get _prefsKey => 'movable_dialog_${widget.dialogId}';

  Future<void> _loadPosition() async {
    if (widget.dialogId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble('${_prefsKey}_x');
    final y = prefs.getDouble('${_prefsKey}_y');
    if (x != null && y != null && mounted) {
      setState(() {
        _offset = Offset(x, y);
      });
    }
  }

  Future<void> _savePosition() async {
    if (widget.dialogId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('${_prefsKey}_x', _offset.dx);
    await prefs.setDouble('${_prefsKey}_y', _offset.dy);
  }

  /// Calculate the nearest screen edge and snap to it if within threshold.
  void _snapToEdge() {
    final ctx = context;
    if (!ctx.mounted) return;

    final size = MediaQuery.sizeOf(ctx);
    final halfW = widget.maxWidth / 2;
    final halfH = widget.maxHeight / 2;

    // Current dialog center = screen center + offset
    final cx = size.width / 2 + _offset.dx;
    final cy = size.height / 2 + _offset.dy;

    final threshold = widget.snapThreshold;

    // Find closest edge
    double? bestDx, bestDy;
    double bestDist = double.infinity;

    // Left edge: dialog left at x=0 → offset.dx = -size.width/2
    final dLeft = (cx - 0).abs();
    if (dLeft < threshold && dLeft < bestDist) {
      bestDist = dLeft;
      bestDx = -size.width / 2 + halfW;
      bestDy = _offset.dy;
    }

    // Right edge: dialog right at x=size.width → offset.dx = size.width/2
    final dRight = (cx - size.width).abs();
    if (dRight < threshold && dRight < bestDist) {
      bestDist = dRight;
      bestDx = size.width / 2 - halfW;
      bestDy = _offset.dy;
    }

    // Top edge: dialog top at y=0 → offset.dy = -size.height/2
    final dTop = (cy - 0).abs();
    if (dTop < threshold && dTop < bestDist) {
      bestDist = dTop;
      bestDy = -size.height / 2 + halfH;
      bestDx = _offset.dx;
    }

    // Bottom edge: dialog bottom at y=size.height → offset.dy = size.height/2
    final dBottom = (cy - size.height).abs();
    if (dBottom < threshold && dBottom < bestDist) {
      bestDy = size.height / 2 - halfH;
      bestDx = _offset.dx;
    }

    if (bestDx != null && bestDy != null) {
      final target = Offset(bestDx, bestDy);
      _snapAnimation = Tween<Offset>(begin: _offset, end: target).animate(
        CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic),
      );
      _snapController.forward(from: 0).then((_) {
        _offset = target;
        _snapAnimation = null;
        _savePosition();
      });
    } else {
      _savePosition();
    }
  }

  void _onPanUpdate(DragUpdateDetails details, void Function(VoidCallback) setState) {
    setState(() {
      _offset += details.delta;
    });
  }

  /// Handle Ctrl+Arrow keyboard shortcuts to move the dialog.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enableKeyboardShortcuts) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
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

    setState(() {
      _offset += delta;
    });
    _snapToEdge();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setInnerState) {
        return AnimatedBuilder(
          animation: _snapController,
          builder: (context, _) {
            return Focus(
              focusNode: _focusNode,
              onKeyEvent: _handleKeyEvent,
              canRequestFocus: false,
              child: Transform.translate(
                offset: _offset,
                child: Dialog(
                child: ConstrainedBox(
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
                          onPanUpdate: (details) {
                            _onPanUpdate(details, setInnerState);
                          },
                          onPanEnd: (_) => _snapToEdge(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Theme.of(context)
                                      .dividerColor
                                      .withValues(alpha: 0.3),
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
                      Flexible(child: widget.child),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
  }
}
