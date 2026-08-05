import 'package:flutter/material.dart';

/// Placeholder for the shared data-list shell.
///
/// PORTING.md §6: AG-Grid has no Flutter equivalent — read-only lists use
/// PlutoGrid with server-side pagination/sort (`PagedRequest`); editable
/// grids (invoice V2 items, PO/quotation/SO lines) use PlutoGrid edit mode.
/// Column order/width/format come from the `*ColumnDefs` files in
/// `references/components/common/MiniERPGrid.tsx`.
class DataTableShell extends StatelessWidget {
  const DataTableShell({super.key, this.title, this.actions, this.body});

  final String? title;
  final List<Widget>? actions;
  final Widget? body;

  @override
  Widget build(BuildContext context) {
    // TODO(porting): PlutoGrid-backed shell with toolbar (search, actions,
    // pagination). See PORTING.md §6.
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: body ?? const SizedBox.shrink(),
      ),
    );
  }
}
