// Production module shell — hosts the production-runs grid and the
// BOM list as tabs (the web app pairs `/production` and `/bom` in the
// same module). Production runs is the branch root (the pre-shell
// `/production` screen), so it is the default tab.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../shell/module_refresh.dart' show moduleTabRefreshOnVisit;
import 'bom_screen.dart';
import 'production_screen.dart';

class ProductionShell extends ConsumerStatefulWidget {
  const ProductionShell({super.key});

  @override
  ConsumerState<ProductionShell> createState() => _ProductionShellState();
}

class _ProductionShellState extends ConsumerState<ProductionShell> {
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
            moduleTabRefreshOnVisit['/production']?[i].call(ref);
          },
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.factory_outlined),
              selectedIcon: const Icon(Icons.factory),
              label: l10n.navProduction,
            ),
            NavigationDestination(
              icon: const Icon(Icons.account_tree_outlined),
              selectedIcon: const Icon(Icons.account_tree),
              label: l10n.navBom,
            ),
          ],
        ),
        Expanded(
          child: IndexedStack(
            index: _index,
            children: const [ProductionScreen(), BomScreen()],
          ),
        ),
      ],
    );
  }
}
