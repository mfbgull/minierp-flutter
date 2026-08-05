import 'package:flutter/material.dart';

/// Colored status chip — port of `references/utils/statusColors.ts`
/// (PORTING.md §6). Pass the status text plus its light/dark colors from
/// the status-color map; e.g. invoice statuses
/// (Unpaid / Partially Paid / Paid / Overdue).
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.status,
    this.color = Colors.blueGrey,
    this.darkColor,
  });

  final String status;
  final Color color;
  final Color? darkColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? darkColor ?? color : color;
    final bg = fg.withValues(alpha: 0.14);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
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
