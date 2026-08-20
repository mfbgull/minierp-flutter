import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/models/search_result.dart' show SearchAction, SearchResult;
import 'recent_items.dart' show RecentItem, recentItemsProvider;
import 'search_navigation.dart' show executeSearchAction, resolveSearchPath;
import 'search_provider.dart'
    show
        searchQueryProvider,
        searchResultsProvider,
        selectedResultProvider;
import 'search_registry.dart' show entityGroupLabel, quickActions, QuickAction;
import 'search_action_panel.dart' show SearchActionPanel;
import 'search_result_tile.dart' show SearchResultTile;

/// Opens the global search palette as a centered modal dialog.
void showGlobalSearchDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) => const GlobalSearchDialog(),
  );
}

class GlobalSearchDialog extends ConsumerStatefulWidget {
  const GlobalSearchDialog({super.key});

  @override
  ConsumerState<GlobalSearchDialog> createState() =>
      _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends ConsumerState<GlobalSearchDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Fresh state each open.
    ref.read(searchQueryProvider.notifier).state = '';
    ref.read(selectedResultProvider.notifier).state = null;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) ref.read(searchQueryProvider.notifier).state = value;
    });
  }

  void _go(String path) {
    Navigator.of(context, rootNavigator: true).pop();
    GoRouter.of(context).go(path);
  }

  void _runAction(SearchResult result, SearchAction action) {
    final path = resolveSearchPath(result, action);
    // Record recent item (best-effort; ignore storage errors).
    ref.read(recentItemsProvider.future).then((recents) {
      recents.addItem(RecentItem(
        entityType: result.type,
        entityId: result.id,
        title: result.title,
        subtitle: result.subtitle,
        path: path,
        timestamp: DateTime.now(),
      ));
    }).catchError((_) {});
    if (!mounted) return;
    executeSearchAction(context, result, action);
  }

  void _onSubmitted(String _) {
    final resp = ref.read(searchResultsProvider).value;
    if (resp == null || resp.results.isEmpty) return;
    final result =
        ref.read(selectedResultProvider) ?? resp.results.first;
    final action = result.actions.isNotEmpty
        ? (result.actions.firstWhere(
            (a) => a.id == 'open',
            orElse: () => result.actions.first,
          ))
        : null;
    if (action != null) _runAction(result, action);
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final resultsAsync = ref.watch(searchResultsProvider);
    final recentsAsync = ref.watch(recentItemsProvider);
    final isWide = MediaQuery.of(context).size.width > 760;
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context, rootNavigator: true).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: Container(
          width: isWide ? 980 : double.infinity,
          height: isWide ? 640 : double.infinity,
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width - 32,
            maxHeight: MediaQuery.of(context).size.height - 48,
          ),
          child: Column(
            children: [
              _SearchBar(
                controller: _controller,
                focusNode: _focusNode,
                onChanged: _onChanged,
                onSubmitted: _onSubmitted,
              ),
              const Divider(height: 1),
              Expanded(
                child: query.trim().length < 2
                    ? _EmptyState(
                        onQuick: _go,
                        recents: recentsAsync.value?.getItems() ?? const [],
                      )
                    : resultsAsync.when(
                        loading: () => const Center(
                          child: CircularProgressIndicator(),
                        ),
                        error: (e, _) => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              '${l10n.searchError}: $e',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        data: (resp) {
                          final list = resp.results;
                          if (list.isEmpty) {
                            return Center(child: Text(l10n.searchNoResults));
                          }
                          final selected = ref.watch(selectedResultProvider);
                          final display = selected ?? list.first;
                          return Row(
                            children: [
                              Expanded(
                                flex: isWide ? 3 : 1,
                                child: _ResultsList(
                                  results: list,
                                  selected: display,
                                  onSelect: (r) => ref
                                      .read(selectedResultProvider.notifier)
                                      .state = r,
                                ),
                              ),
                              if (isWide) ...[
                                VerticalDivider(
                                  width: 1,
                                  color: scheme.outlineVariant,
                                ),
                                Expanded(
                                  flex: 2,
                                  child: SearchActionPanel(
                                    result: display,
                                    onAction: (action) => _runAction(display, action),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: true,
        decoration: InputDecoration(
          hintText: l10n.searchHint,
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          isDense: true,
          suffixIcon: IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.searchClose,
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(),
          ),
        ),
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.results,
    required this.selected,
    required this.onSelect,
  });

  final List<SearchResult> results;
  final SearchResult? selected;
  final ValueChanged<SearchResult> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groups = <String, List<SearchResult>>{};
    for (final r in results) {
      groups.putIfAbsent(r.type, () => []).add(r);
    }
    return ListView(
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              entityGroupLabel[entry.key] ?? entry.key.toUpperCase(),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          for (final r in entry.value)
            SearchResultTile(
              result: r,
              selected: identical(r, selected),
              onTap: () => onSelect(r),
            ),
        ],
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onQuick, required this.recents});

  final ValueChanged<String> onQuick;
  final List<RecentItem> recents;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final List<QuickAction> actions = quickActions;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l10n.searchQuickActions,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final QuickAction q in actions)
              FilledButton.tonal(
                onPressed: () => onQuick(q.path),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(q.icon, size: 18),
                    const SizedBox(width: 8),
                    Text(q.label),
                  ],
                ),
              ),
          ],
        ),
        if (recents.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            l10n.searchRecent,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          for (final r in recents.take(5))
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(r.title),
              subtitle: r.subtitle.isNotEmpty ? Text(r.subtitle) : null,
              onTap: () => onQuick(r.path),
              dense: true,
            ),
        ],
      ],
    );
  }
}
