// BOM list — a read-only grid over `GET /boms` (**bare array** — no
// search/page params, so sorting and filtering stay client-side).
// Rendered with PlutoGrid via the shared [PlutoGridScreen] mixin:
// F2/Enter + double-tap open the BOM detail; the keyboard-hint
// status bar sits beneath the grid. Sits on the `BOM` tab of the
// production shell (the web app hosts the BOM list at `/bom`).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/bom.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/status_badge.dart';
import 'bom_detail_dialog.dart';
import 'bom_form_dialog.dart';
import 'production_providers.dart';

class BomScreen extends ConsumerStatefulWidget {
  const BomScreen({super.key});

  @override
  ConsumerState<BomScreen> createState() => _BomScreenState();
}

class _BomScreenState extends ConsumerState<BomScreen>
    with PlutoGridScreen<Bom, BomScreen> {
  @override
  void openRowDetail(int bomId) {
    if (!mounted) return;
    showBomDetailDialog(context, bomId: bomId);
  }

  @override
  PlutoRow gridRowFor(Bom bom) => PlutoRow(
    cells: {
      'id': PlutoCell(value: bom.id),
      'bomNo': PlutoCell(value: bom.bomNo),
      'name': PlutoCell(value: bom.bomName),
      'finished': PlutoCell(
        value: bom.finishedItemName ?? bom.finishedItemCode ?? '',
      ),
      'qty': PlutoCell(value: bom.quantity),
      'uom': PlutoCell(value: bom.finishedUom ?? ''),
      'items': PlutoCell(value: bom.itemCount ?? 0),
      'cost': PlutoCell(value: bom.totalMaterialCost ?? 0),
      'active': PlutoCell(value: bom.isActive),
    },
  );

  @override
  Widget build(BuildContext context) {
    final boms = ref.watch(bomsProvider);
    final l10n = AppLocalizations.of(context)!;

    watchGridProvider(bomsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => showBomFormDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.bomNewbom),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: boms.isLoading || (boms.valueOrNull?.isEmpty ?? true)
                    ? null
                    : () => saveCsv(
                        context,
                        suggestedName: csvSuggestedName('boms'),
                        csv: buildBomsCsv(l10n, boms.valueOrNull!),
                        successMessage: l10n.bomExported,
                        errorMessage: l10n.bomExportfailed,
                      ),
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: Text(l10n.bomExportcsv),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: l10n.commonRefresh,
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(bomsProvider),
              ),
            ],
          ),
        ),
        Expanded(child: gridScreenBody(boms, provider: bomsProvider)),
      ],
    );
  }

  @override
  List<PlutoColumn> buildGridColumns(AppLocalizations l10n) {
    PlutoColumn textColumn(String field, String title, double width) =>
        PlutoColumn(
          title: title,
          field: field,
          type: PlutoColumnType.text(),
          width: width,
          readOnly: true,
          enableContextMenu: false,
        );

    return [
      PlutoColumn(
        title: '',
        field: 'id',
        type: PlutoColumnType.number(),
        width: 80,
        readOnly: true,
        renderer: (ctx) => const SizedBox.shrink(),
        enableContextMenu: false,
        enableFilterMenuItem: false,
        enableHideColumnMenuItem: false,
        enableSetColumnsMenuItem: false,
      ),
      textColumn('bomNo', l10n.bomNo, 120),
      textColumn('name', l10n.bomName, 220),
      textColumn('finished', l10n.bomFinisheditem, 240),
      PlutoColumn(
        title: l10n.commonQuantity,
        field: 'qty',
        type: PlutoColumnType.number(format: '#,###.000'),
        width: 90,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        renderer: (ctx) => Align(
          alignment: Alignment.centerRight,
          child: Text(Formatters.number(ctx.cell.value as num? ?? 0)),
        ),
      ),
      textColumn('uom', l10n.commonUom, 80),
      PlutoColumn(
        title: l10n.bomItems,
        field: 'items',
        type: PlutoColumnType.number(),
        width: 90,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        renderer: (ctx) => Align(
          alignment: Alignment.centerRight,
          child: Text('${ctx.cell.value}'),
        ),
      ),
      PlutoColumn(
        title: l10n.bomMaterialcost,
        field: 'cost',
        type: PlutoColumnType.number(format: '#,###.00'),
        width: 120,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.right,
        titleTextAlign: PlutoColumnTextAlign.right,
        enableContextMenu: false,
        renderer: (ctx) => Align(
          alignment: Alignment.centerRight,
          child: Text(Formatters.currency(ctx.cell.value as num? ?? 0)),
        ),
      ),
      PlutoColumn(
        title: l10n.commonStatus,
        field: 'active',
        type: PlutoColumnType.text(),
        width: 110,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final active = ctx.cell.value == true;
            final l10n = AppLocalizations.of(cellContext)!;
            return Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(
                status: active ? l10n.statusActive : l10n.statusInactive,
                color: active
                    ? const Color(0xFF059669)
                    : const Color(0xFF6B7280),
                darkColor: active
                    ? const Color(0xFF10B981)
                    : const Color(0xFF86EFAC),
              ),
            );
          },
        ),
      ),
    ];
  }
}
