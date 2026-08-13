import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/preferences/preference_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
