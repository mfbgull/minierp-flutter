import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/app_support_paths.dart';
import 'features/preferences/preference_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Linux only: point the shared_preferences store at ~/.local/share/minierp
  // and migrate the legacy id folders (com.example.minierp_app from old
  // installs, com.example.minierp from the id rename — docs/bugs.md BUG-009). Both must run before the first SharedPreferences access — the
  // PreferencesCache.load below is that first access.
  if (Platform.isLinux) {
    AppSupportPaths.installPreferencesOverride();
    AppSupportPaths.migratePreferences();
  }
  // Preload the cached date-range preferences (week start, default range,
  // user presets) before the first frame so the preference StateProviders
  // seed synchronously (date-range-picker-spec.md §6.2: local cache =
  // seed, server = truth). The server fetch fires at shell boot and wins
  // on arrival; the cache only stands in when it's offline/unresolved.
  final cache = await PreferencesCache.load();
  runApp(
    ProviderScope(
      overrides: [preferencesCacheProvider.overrideWithValue(cache)],
      child: const MiniErpApp(),
    ),
  );
}
