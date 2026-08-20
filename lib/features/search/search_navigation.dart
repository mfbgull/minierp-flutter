import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/search_result.dart' show SearchAction, SearchResult;
import 'search_registry.dart' show actionPath, entityModulePath;

/// Resolves the navigation target for a (result, action) pair:
/// 1. page results carry their own `path` in metadata;
/// 2. explicit action→path overrides win next;
/// 3. `open` on a customer/supplier uses the detail route when we have
///    an id, otherwise the module root;
/// 4. anything else falls back to the entity's module root.
String resolveSearchPath(SearchResult result, SearchAction action) {
  if (result.isPage) {
    final p = result.metadata['path'];
    if (p is String && p.isNotEmpty) return p;
  }
  final explicit = actionPath[action.id];
  if (explicit != null && explicit.isNotEmpty) return explicit;

  if (action.id == 'open' &&
      (result.type == 'customer' || result.type == 'supplier')) {
    final id = result.id;
    if (id is num) return '${entityModulePath[result.type]}/$id';
  }
  return entityModulePath[result.type] ?? '/';
}

/// Closes the search dialog and navigates to the resolved target.
void executeSearchAction(
  BuildContext context,
  SearchResult result,
  SearchAction action,
) {
  final router = GoRouter.of(context);
  Navigator.of(context, rootNavigator: true).pop();
  router.go(resolveSearchPath(result, action));
}
