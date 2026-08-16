// Dashboard customizer dialog (spec §6.2) — the single dialog behind
// the toolbar "Customize" button. Shows every available dashboard block
// — KPI cards, content panels, and the cash & bank strip — grouped into
// sections, each with a visibility checkbox, a search filter, Select
// All / Clear All, and Save (persists to the server) / Done (closes).
//
// Live preview: toggles update the shared layout controller, so the
// dashboard behind the dialog reflects changes immediately; only Save
// persists them (spec §2).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/dashboard_layout.dart'
    show DashboardBlock, DashboardBlockSize;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart' show showAppToast;
import 'dashboard_kpi_catalog.dart'
    show kpiCardById, kpiCardHint, kpiCardLabel;
import 'dashboard_layout_controller.dart'
    show dashboardLayoutControllerProvider;
import 'dashboard_panel_catalog.dart'
    show cashStripDefinition, dashboardPanelLabel, panelById;

/// Opens the customizer dialog from the dashboard toolbar.
Future<void> showDashboardCustomizerDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const DashboardCustomizerDialog(),
  );
}

class DashboardCustomizerDialog extends ConsumerStatefulWidget {
  const DashboardCustomizerDialog({super.key});

  @override
  ConsumerState<DashboardCustomizerDialog> createState() =>
      _DashboardCustomizerDialogState();
}

class _DashboardCustomizerDialogState
    extends ConsumerState<DashboardCustomizerDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final layout = ref.watch(dashboardLayoutControllerProvider);
    final controller = ref.read(dashboardLayoutControllerProvider.notifier);

    // Search filters by localized title (catalog label, not the
    // persisted title — titles come from l10n keys, spec §9).
    final query = _query.trim().toLowerCase();
    bool matches(DashboardBlock block) {
      if (query.isEmpty) return true;
      final label = switch (block) {
        _ when kpiCardById.containsKey(block.id) =>
          kpiCardLabel(l10n, kpiCardById[block.id]!.labelKey),
        _ when panelById.containsKey(block.id) =>
          dashboardPanelLabel(l10n, panelById[block.id]!.labelKey),
        _ when block.id == cashStripDefinition.id =>
          dashboardPanelLabel(l10n, cashStripDefinition.labelKey),
        _ => block.title,
      };
      return label.toLowerCase().contains(query);
    }

    final kpiBlocks = [
      for (final block in layout.blocks)
        if (kpiCardById.containsKey(block.id) && matches(block)) block,
    ];
    final panelBlocks = [
      for (final block in layout.blocks)
        if (panelById.containsKey(block.id) && matches(block)) block,
    ];
    final cashBlocks = [
      for (final block in layout.blocks)
        if (block.id == cashStripDefinition.id && matches(block)) block,
    ];
    final visibleCount = layout.blocks.where((b) => b.visible).length;

    return AlertDialog(
      title: Text(l10n.dashboardcustomizationCustomize),
      content: SizedBox(
        width: 440,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Search field (spec: searchable flat list).
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: l10n.dashboardcardsSearch,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Select All / Clear All.
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => controller.setAllVisible(true),
                  icon: const Icon(Icons.select_all, size: 16),
                  label: Text(l10n.dashboardcardsSelectall),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () => controller.setAllVisible(false),
                  icon: const Icon(Icons.deselect, size: 16),
                  label: Text(l10n.dashboardcardsClearall),
                ),
                const Spacer(),
                Text(
                  '$visibleCount/${layout.blocks.length}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView(
                children: [
                  if (kpiBlocks.isNotEmpty)
                    _SectionHeader(label: l10n.dashboardcardsKpis),
                  if (kpiBlocks.isNotEmpty)
                    _BuildSection(
                      blocks: kpiBlocks,
                      reorderable: query.isEmpty,
                      onReorder: (oldIndex, newIndex) =>
                          controller.reorderDialogKpis(oldIndex, newIndex),
                    ),
                  if (panelBlocks.isNotEmpty)
                    _SectionHeader(label: l10n.dashboardcardsPanels),
                  if (panelBlocks.isNotEmpty)
                    _BuildSection(
                      blocks: panelBlocks,
                      reorderable: query.isEmpty,
                      onReorder: (oldIndex, newIndex) =>
                          _reorderPanels(panelBlocks, oldIndex, newIndex),
                    ),
                  if (cashBlocks.isNotEmpty)
                    _SectionHeader(label: l10n.dashboardcardsCashbank),
                  for (final block in cashBlocks) _BlockRow(block: block),
                  if (kpiBlocks.isEmpty &&
                      panelBlocks.isEmpty &&
                      cashBlocks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Center(
                        child: Text(
                          l10n.commonNoresults,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (layout.dirty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.dashboardcustomizationUnsaved,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _revertToDefault(l10n),
          child: Text(l10n.dashboardcustomizationRevert),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.dashboardcustomizationDone),
        ),
        FilledButton(
          onPressed: layout.saving ? null : () => _save(l10n),
          child: layout.saving
              ? Text(l10n.dashboardcustomizationSaving)
              : Text(l10n.dashboardcustomizationSave),
        ),
      ],
    );
  }

  /// Row-scopes a panel drag from the dialog's flat Panels section
  /// (spec §6.5: panels reorder within their rows only). The section
  /// lists every panel (visible + hidden) in layout order, so we map
  /// the flat old/new indices to row-local ones before reordering.
  ///
  /// `onReorderItem` reports `newIndex` as the insertion position in
  /// the list *after* the moved item has been removed, so each
  /// remaining same-row panel's index is shifted down by one when it
  /// sat after `oldIndex`.
  void _reorderPanels(
    List<DashboardBlock> panels,
    int oldIndex,
    int newIndex,
  ) {
    if (oldIndex < 0 || oldIndex >= panels.length) return;
    final moved = panels[oldIndex];
    final row = panelById[moved.id]?.row;
    if (row == null) return;
    // Flat indices of this row's panels (excluding the moved one).
    final remaining = <int>[
      for (var i = 0; i < panels.length; i++)
        if (i != oldIndex && panelById[panels[i].id]?.row == row) i,
    ];
    if (remaining.isEmpty) return;
    final oldLocal = remaining
        .where((p) => p < oldIndex)
        .length; // row-local index of the moved panel
    // Row-local insertion point: count remaining row panels whose
    // post-removal flat index falls before the target.
    final newLocal = remaining
        .where(
          (p) => (p < oldIndex ? p : p - 1) < newIndex,
        )
        .length;
    ref
        .read(dashboardLayoutControllerProvider.notifier)
        .reorderDialogPanels(row, oldLocal, newLocal.clamp(0, remaining.length));
  }

  /// Revert to the curated default — with a confirm (the action is
  /// destructive: it discards the current visibility + order).
  Future<void> _revertToDefault(AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.dashboardcustomizationRevertconfirmtitle),
        content: Text(l10n.dashboardcustomizationRevertconfirmmsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.dashboardcustomizationRevert),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // Reset to the curated default; stays dirty until Save (mirrors the
    // web app's "revert" → user confirms → Save persists).
    ref.read(dashboardLayoutControllerProvider.notifier).revertToDefault();
    if (mounted) showAppToast(context, l10n.dashboardcustomizationReverted);
  }

  Future<void> _save(AppLocalizations l10n) async {
    final error = await ref
        .read(dashboardLayoutControllerProvider.notifier)
        .save();
    if (!mounted) return;
    if (error == null) {
      showAppToast(context, l10n.dashboardcustomizationLayoutsaved);
      Navigator.of(context).pop();
    } else {
      showAppToast(
        context,
        '${l10n.dashboardcustomizationSavefailed}: ${error.message}',
        isError: true,
      );
    }
  }
}

/// Section heading between block groups (KPI Cards / Panels / Cash &
/// Bank).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// One checkbox + label row in the dialog — toggling writes straight to
/// the shared controller (live preview). Resolves the block's label +
/// icon from whichever catalog owns its id (KPI / panel / cash). When
/// [dragIndex] is set the row is draggable and shows a drag handle
/// (spec §6.2 row: checkbox · title · size · drag handle).
class _BlockRow extends ConsumerWidget {
  const _BlockRow({super.key, required this.block, this.dragIndex});

  final DashboardBlock block;

  /// Row-local index for the reorder drag handle; null → not draggable.
  final int? dragIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final controller = ref.read(dashboardLayoutControllerProvider.notifier);

    final kpiDef = kpiCardById[block.id];
    final panelDef = panelById[block.id];
    final IconData icon;
    final String label;
    final String? hint;
    if (kpiDef != null) {
      icon = kpiDef.icon;
      label = kpiCardLabel(l10n, kpiDef.labelKey);
      hint = kpiCardHint(l10n, kpiDef.hintKey);
    } else if (panelDef != null) {
      icon = panelDef.icon;
      label = dashboardPanelLabel(l10n, panelDef.labelKey);
      hint = null;
    } else {
      icon = Icons.savings_outlined;
      label = dashboardPanelLabel(l10n, cashStripDefinition.labelKey);
      hint = null;
    }

    // The cash strip is fixed — show/hide only, no size control
    // (spec §6.3). KPI cards + panels get the Small/Medium/Large
    // selector.
    final isCash = block.id == cashStripDefinition.id;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Checkbox(
        value: block.visible,
        onChanged: (value) => controller.toggle(block.id, value ?? false),
      ),
      title: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
      subtitle: hint == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
      trailing: isCash
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SizeSelector(block: block),
                if (dragIndex != null)
                  ReorderableDragStartListener(
                    index: dragIndex!,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(
                        Icons.drag_indicator,
                        size: 18,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
              ],
            ),
      onTap: () => controller.toggle(block.id, !block.visible),
    );
  }
}

/// A reorderable run of block rows inside the dialog (KPI Cards /
/// Panels sections). Drag handles reorder the run; `onReorderItem`
/// reports flat indices into [blocks]. Disabled while the search box is
/// filtering (indices wouldn't map to the full layout).
class _BuildSection extends ConsumerWidget {
  const _BuildSection({
    required this.blocks,
    required this.reorderable,
    required this.onReorder,
  });

  final List<DashboardBlock> blocks;
  final bool reorderable;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!reorderable) {
      return Column(
        children: [for (final block in blocks) _BlockRow(block: block)],
      );
    }
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) =>
          onReorder(oldIndex, newIndex),
      children: [
        for (var i = 0; i < blocks.length; i++)
          _BlockRow(
            key: ValueKey('dialog-${blocks[i].id}'),
            block: blocks[i],
            dragIndex: i,
          ),
      ],
    );
  }
}

/// Compact Small / Medium / Large selector for one block (spec §6.3).
/// Uses the shared `dashboardcustomization*` size keys. The cash strip
/// is fixed and doesn't render one.
class _SizeSelector extends ConsumerWidget {
  const _SizeSelector({required this.block});

  final DashboardBlock block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final controller = ref.read(dashboardLayoutControllerProvider.notifier);
    final size = block.config.size ?? DashboardBlockSize.medium;
    final label = switch (size) {
      DashboardBlockSize.small => l10n.dashboardcustomizationSmall,
      DashboardBlockSize.medium => l10n.dashboardcustomizationMedium,
      DashboardBlockSize.large => l10n.dashboardcustomizationLarge,
    };

    return PopupMenuButton<DashboardBlockSize>(
      tooltip: l10n.dashboardcustomizationSize,
      initialValue: size,
      onSelected: (value) => controller.setSize(block.id, value),
      itemBuilder: (context) => [
        for (final option in DashboardBlockSize.values)
          PopupMenuItem(
            value: option,
            child: Text(
              switch (option) {
                DashboardBlockSize.small => l10n.dashboardcustomizationSmall,
                DashboardBlockSize.medium => l10n
                    .dashboardcustomizationMedium,
                DashboardBlockSize.large => l10n.dashboardcustomizationLarge,
              },
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
