// Settings providers — one future that loads the full key-value store
// (`GET /settings`) for the SettingsScreen's grouped editor. The screen
// holds the editable field state locally (no per-key providers); refresh
// simply invalidates this future.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/setting.dart' show AppSetting;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/settings_repository.dart'
    show settingsRepositoryProvider;

/// All settings keyed by `key`, in server row order.
final settingsProvider = FutureProvider<Map<String, AppSetting>>((ref) async {
  final result = await ref.watch(settingsRepositoryProvider).all();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Current display-only currency configuration, with safe defaults while
/// settings are loading or unavailable.
final currencyConfigProvider = Provider<CurrencyConfig>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  final config = CurrencyConfig.fromValues(
    symbol: settings?['currency_symbol']?.value,
    code: settings?['currency_code']?.value,
  );
  CurrencyConfigStore.set(config);
  return config;
});

/// Formatter used by user-facing monetary displays and exports.
final currencyFormatterProvider = Provider<CurrencyFormatter>((ref) {
  return CurrencyFormatter(ref.watch(currencyConfigProvider));
});
