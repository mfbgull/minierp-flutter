import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../shell/module_refresh.dart' show moduleTabRefreshOnVisit;
import 'items_screen.dart';
import 'physical_count_screen.dart';
import 'stock_by_warehouse_screen.dart';
import 'stock_movement_screen.dart';
import 'warehouses_screen.dart';

class InventoryShell extends ConsumerStatefulWidget {
  const InventoryShell({super.key});

  @override
  ConsumerState<InventoryShell> createState() => _InventoryShellState();
}

class _InventoryShellState extends ConsumerState<InventoryShell> {
  // Items is the branch root (the pre-shell `/inventory` screen) — the
  // stock/warehouse views are reachable via the tabs.
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            setState(() => _index = i);
            // Refresh the clicked tab's data (the IndexedStack keeps
            // every tab alive, so its providers would stay cached).
            moduleTabRefreshOnVisit['/inventory']?[i].call(ref);
          },
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.inventory_2_outlined),
              selectedIcon: const Icon(Icons.inventory_2),
              label: l10n.navItems,
            ),
            NavigationDestination(
              icon: const Icon(Icons.warehouse_outlined),
              selectedIcon: const Icon(Icons.warehouse),
              label: l10n.navWarehouses,
            ),
            NavigationDestination(
              icon: const Icon(Icons.swap_horiz_outlined),
              selectedIcon: const Icon(Icons.swap_horiz),
              label: l10n.navStockmovements,
            ),
            NavigationDestination(
              icon: const Icon(Icons.map_outlined),
              selectedIcon: const Icon(Icons.map),
              label: l10n.navStockbywarehouse,
            ),
            NavigationDestination(
              icon: const Icon(Icons.calculate_outlined),
              selectedIcon: const Icon(Icons.calculate),
              label: l10n.navPhysicalcounts,
            ),
          ],
        ),
        Expanded(
          child: IndexedStack(
            index: _index,
            children: const [
              ItemsScreen(),
              WarehousesScreen(),
              StockMovementScreen(),
              StockByWarehouseScreen(),
              PhysicalCountScreen(),
            ],
          ),
        ),
      ],
    );
  }
}
