// Unit tests for the dashboard layout controller (the dashboard
// customizer's working state): curated default fallback, saved-layout
// merge, toggle / select-all, KPI-strip + panel-row reorder, and the
// create-then-update save flow. The repository is driven by the same
// fake-Dio adapter pattern as repositories_test.dart — no live server.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/dashboard_layout.dart'
    show DashboardBlockSize;
import 'package:minierp_app/data/repositories/dashboard_layout_repository.dart'
    show DashboardLayoutRepository;
import 'package:minierp_app/data/repositories/repository_client.dart'
    show RepositoryClient;
import 'package:minierp_app/features/dashboard/dashboard_layout_controller.dart'
    show DashboardLayoutController;


typedef RouteHandler = ResponseBody Function(RequestOptions options);

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final RouteHandler handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// Total catalog size: 16 KPI cards + 5 panels + 1 cash strip.
const int _totalBlocks = 22;

void main() {
  late RouteHandler handler;
  late DashboardLayoutRepository repo;
  late DashboardLayoutController controller;

  setUp(() {
    handler = (_) => _json({'success': true, 'data': null}, status: 404);
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost:3011/api'));
    dio.httpClientAdapter = _FakeAdapter((options) => handler(options));
    repo = DashboardLayoutRepository(RepositoryClient(dio));
    controller = DashboardLayoutController(repo);
  });

  tearDown(() => controller.dispose());

  /// Waits for the controller's async `_load()` to finish (the fake
  /// Dio adapter resolves over a few microtask/event-loop turns). A
  /// fixed delay of 20ms races the cold JIT path and parallel-suite
  /// CPU contention (the load can take longer than 20ms, leaving the
  /// state at its initial value); 200ms gives the chain comfortable
  /// margin without materially slowing the file.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 200));

  List<String> visibleIds() => [
    for (final b in controller.state.blocks)
      if (b.visible) b.id,
  ];

  group('curated default (no saved layout)', () {
    test('shows 4 KPI cards + 3 panels + cash strip, everything else off', () async {
      await settle();
      expect(
        visibleIds(),
        [
          'kpi_stock_value',
          'kpi_sales_revenue',
          'kpi_gross_profit',
          'kpi_purchase_orders',
          'panel_sales_purchases',
          'panel_ar_aging',
          'panel_low_stock',
          'cash_strip',
        ],
      );
      expect(controller.state.layoutId, isNull);
      expect(controller.state.saved, isFalse);
      // All catalog blocks are present (hidden ones available to enable).
      expect(controller.state.blocks.length, _totalBlocks);
    });

    test('server failure falls back to the curated default too', () async {
      handler = (_) => _json({'error': 'boom'}, status: 500);
      await settle();
      expect(controller.state.blocks.length, _totalBlocks);
      expect(controller.state.saved, isFalse);
    });
  });

  group('saved layout merge', () {
    test('known blocks keep saved order/visibility; unknown ids dropped', () async {
      handler = (_) => _json({
        'success': true,
        'data': {
          'id': 7,
          'user_id': 1,
          'layout_name': 'Default',
          'is_active': true,
          'blocks': [
            {
              'id': 'kpi_ar',
              'type': 'kpi',
              'title': 'dashboardcardAr',
              'x': 0,
              'y': 0,
              'width': 188,
              'height': 84,
              'visible': true,
              'version': 1,
              'config': {'metric': 'outstanding_receivables'},
            },
            {
              'id': 'panel_stock_by_category',
              'type': 'panel',
              'title': 'dashboardcardPanelStockbycategory',
              'x': 0,
              'y': 2,
              'width': 2,
              'height': 1,
              'visible': true,
              'version': 1,
              'config': {},
            },
            {'id': 'old-block-that-no-longer-exists', 'type': 'x', 'title': 'X', 'x': 0, 'y': 0, 'width': 1, 'height': 1, 'visible': true, 'version': 1, 'config': {}},
          ],
        },
      });
      await settle();
      expect(controller.state.layoutId, 7);
      expect(controller.state.saved, isTrue);
      final ids = [for (final b in controller.state.blocks) b.id];
      // AR + stock-by-category first (saved order), the unknown block
      // dropped, then the rest of the catalog appended hidden.
      expect(ids.first, 'kpi_ar');
      expect(ids[1], 'panel_stock_by_category');
      expect(ids, isNot(contains('old-block-that-no-longer-exists')));
      expect(ids.length, _totalBlocks);
      expect(controller.state.blocks.first.visible, isTrue);
    });
  });

  group('toggle / select-all', () {
    test('toggle flips visibility and marks dirty', () async {
      await settle();
      controller.toggle('kpi_ar', true);
      expect(
        [for (final b in controller.state.blocks) if (b.id == 'kpi_ar') b.visible],
        [true],
      );
      expect(controller.state.dirty, isTrue);
    });

    test('setAllVisible(false) hides everything', () async {
      await settle();
      controller.setAllVisible(false);
      expect(visibleIds(), isEmpty);
    });
  });

  group('KPI strip reorder', () {
    test('reorders visible KPI cards while hidden cards + panels stay put', () async {
      await settle();
      // Default: 4 visible KPI cards in catalog order. Move the last
      // visible (PO's) to the front.
      controller.reorder(3, 0);
      final visible = [
        for (final b in controller.state.blocks)
          if (b.visible && b.id.startsWith('kpi_')) b.id,
      ];
      expect(
        visible,
        ['kpi_purchase_orders', 'kpi_stock_value', 'kpi_sales_revenue', 'kpi_gross_profit'],
      );
      // Hidden KPI cards keep their positions in the full list.
      expect(
        [
          for (final b in controller.state.blocks)
            if (!b.visible && b.id.startsWith('kpi_')) b.id,
        ],
        [
          'kpi_total_items',
          'kpi_wh_stock',
          'kpi_ar',
          'kpi_inventory_turnover',
          'kpi_avg_days_to_pay',
          'kpi_stock_health',
          'kpi_monthly_revenue',
          'kpi_net_profit',
          'kpi_expenses',
          'kpi_payables',
          'kpi_customers',
          'kpi_low_stock',
        ],
      );
      // Panels unaffected (first panel now sits after the 16 KPI cards).
      expect(controller.state.blocks[16].id, 'panel_sales_purchases');
      expect(controller.state.dirty, isTrue);
    });
  });

  group('size control', () {
    test('setSize updates config.size and marks dirty', () async {
      await settle();
      controller.setSize('kpi_stock_value', DashboardBlockSize.large);
      final block = controller.state.blocks.firstWhere(
        (b) => b.id == 'kpi_stock_value',
      );
      expect(block.config.size, DashboardBlockSize.large);
      expect(controller.state.dirty, isTrue);
    });

    test('size round-trips through the saved layout payload', () async {
      await settle();
      // Medium is the default and is not emitted (spec §6.3 — old
      // layouts round-trip unchanged); large is.
      controller.setSize('kpi_stock_value', DashboardBlockSize.medium);
      controller.setSize('kpi_sales_revenue', DashboardBlockSize.large);
      controller.setSize('panel_low_stock', DashboardBlockSize.small);

      List<dynamic>? sent;
      handler = (o) {
        sent = (o.data as Map<String, dynamic>)['blocks'] as List<dynamic>;
        return _json({'success': true, 'message': 'Layout updated'});
      };
      await controller.save();

      final stockValue = sent!.firstWhere(
        (b) => (b as Map<String, dynamic>)['id'] == 'kpi_stock_value',
      ) as Map<String, dynamic>;
      // Medium → not emitted.
      expect((stockValue['config'] as Map<String, dynamic>).containsKey('size'), isFalse);

      final salesRevenue = sent!.firstWhere(
        (b) => (b as Map<String, dynamic>)['id'] == 'kpi_sales_revenue',
      ) as Map<String, dynamic>;
      expect(
        ((salesRevenue['config'] as Map<String, dynamic>)['size']),
        'large',
      );

      final lowStock = sent!.firstWhere(
        (b) => (b as Map<String, dynamic>)['id'] == 'panel_low_stock',
      ) as Map<String, dynamic>;
      expect(
        ((lowStock['config'] as Map<String, dynamic>)['size']),
        'small',
      );
    });

    test('saved size is restored on load', () async {
      handler = (_) => _json({
        'success': true,
        'data': {
          'id': 7,
          'user_id': 1,
          'layout_name': 'Default',
          'is_active': true,
          'blocks': [
            {
              'id': 'kpi_ar',
              'type': 'kpi',
              'title': 'dashboardcardAr',
              'x': 0,
              'y': 0,
              'width': 260,
              'height': 84,
              'visible': true,
              'version': 1,
              'config': {'metric': 'outstanding_receivables', 'size': 'large'},
            },
          ],
        },
      });
      await settle();
      final block = controller.state.blocks.firstWhere(
        (b) => b.id == 'kpi_ar',
      );
      expect(block.config.size, DashboardBlockSize.large);
    });
  });

  group('dialog reorder (drag handles in the dialog, §6.2)', () {
    test('reorderDialogKpis reorders the full KPI list (hidden included)', () async {
      await settle();
      // All KPI cards in catalog order; move the hidden AR card to the
      // front of the full list (visible strip order follows).
      controller.reorderDialogKpis(6, 0);
      final kpis = [
        for (final b in controller.state.blocks)
          if (b.id.startsWith('kpi_')) b.id,
      ];
      expect(kpis.first, 'kpi_ar');
      // Visible strip order now starts with AR (still off) then the
      // default four.
      expect(kpis.take(5).toList(), [
        'kpi_ar',
        'kpi_total_items',
        'kpi_stock_value',
        'kpi_sales_revenue',
        'kpi_gross_profit',
      ]);
      expect(controller.state.dirty, isTrue);
    });

    test('reorderDialogPanels reorders within a row (row-scoped)', () async {
      await settle();
      // Row 2 in catalog order: stock_by_category, top_customers,
      // low_stock. The dialog's flat panel list interleaves rows, so
      // row 2's flat positions are [2, 3, 4]. Move low_stock (flat 4)
      // to flat 2 (row-local 0).
      controller.reorderDialogPanels(2, 2, 0);
      expect(
        [
          for (final b in controller.state.blocks)
            if (b.id.startsWith('panel_') && b.y == 2) b.id,
        ],
        ['panel_low_stock', 'panel_stock_by_category', 'panel_top_customers'],
      );
      // Row 1 unchanged.
      expect(
        [
          for (final b in controller.state.blocks)
            if (b.id.startsWith('panel_') && b.y == 1) b.id,
        ],
        ['panel_sales_purchases', 'panel_ar_aging'],
      );
      expect(controller.state.dirty, isTrue);
    });
  });

  group('panel row reorder', () {
    test('reorders visible panels within row 2 while row 1 stays put', () async {
      await settle();
      // Default row 2: Stock by Category (off), Top Customers (off),
      // Low Stock (on). Enable the others first, then move Low Stock
      // from position 2 to 0.
      controller.toggle('panel_stock_by_category', true);
      controller.toggle('panel_top_customers', true);
      controller.reorderPanels(2, 2, 0);
      expect(
        [
          for (final b in controller.state.blocks)
            if (b.visible && b.id.startsWith('panel_') && b.y == 2) b.id,
        ],
        ['panel_low_stock', 'panel_stock_by_category', 'panel_top_customers'],
      );
      // Row 1 unchanged.
      expect(
        [
          for (final b in controller.state.blocks)
            if (b.visible && b.id.startsWith('panel_') && b.y == 1) b.id,
        ],
        ['panel_sales_purchases', 'panel_ar_aging'],
      );
      expect(controller.state.dirty, isTrue);
    });
  });

  group('save flow', () {
    test('first save POSTs, remembers the id, later saves PUT', () async {
      await settle();
      final calls = <String>[];
      handler = (o) {
        calls.add('${o.method} ${o.path}');
        if (o.method == 'POST') {
          return _json({
            'success': true,
            'data': {
              'id': 9,
              'user_id': 1,
              'layout_name': 'Default',
              'is_active': true,
              'blocks': o.data is Map<String, dynamic>
                  ? o.data!['blocks'] as List
                  : const [],
            },
          }, status: 201);
        }
        return _json({'success': true, 'message': 'Layout updated'});
      };

      final firstError = await controller.save();
      expect(firstError, isNull);
      expect(controller.state.layoutId, 9);
      expect(controller.state.dirty, isFalse);

      controller.toggle('kpi_ar', true);
      final secondError = await controller.save();
      expect(secondError, isNull);
      expect(calls, ['POST /dashboard/layout', 'PUT /dashboard/layout/9']);
    });

    test('save failure surfaces the server error and keeps dirty', () async {
      await settle();
      handler = (_) => _json({'error': 'Layout name already exists'}, status: 409);
      final error = await controller.save();
      expect(error, isNotNull);
      expect(error!.message, 'Layout name already exists');
      expect(controller.state.saving, isFalse);
    });
  });

  group('revert to default', () {
    test('resets blocks to the curated default and marks dirty', () async {
      await settle();
      controller.toggle('kpi_ar', true);
      controller.toggle('panel_low_stock', false);
      controller.revertToDefault();
      expect(
        visibleIds(),
        [
          'kpi_stock_value',
          'kpi_sales_revenue',
          'kpi_gross_profit',
          'kpi_purchase_orders',
          'panel_sales_purchases',
          'panel_ar_aging',
          'panel_low_stock',
          'cash_strip',
        ],
      );
      expect(controller.state.dirty, isTrue);
    });
  });
}
