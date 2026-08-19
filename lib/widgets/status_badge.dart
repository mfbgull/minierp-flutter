import 'package:flutter/material.dart';

import '../core/theme/app_border_radius.dart';

/// Colored status chip — M3-aware: uses tonal surface tinting for the
/// background instead of hardcoded alpha.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.status,
    this.color,
    @Deprecated('M3 handles dark mode natively via ColorScheme')
    this.darkColor,
  });

  final String status;
  final Color? color;
  @Deprecated('M3 handles dark mode natively via ColorScheme')
  final Color? darkColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.outline;
    final bg = fg.withValues(alpha: 0.14);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppBorderRadius.badge,
      ),
      child: Text(
        status,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
