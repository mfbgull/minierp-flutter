import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minierp_app/core/utils/formatters.dart';
import 'package:minierp_app/data/models/setting.dart';
import 'package:minierp_app/features/settings/settings_providers.dart';

void main() {
  tearDown(CurrencyConfigStore.reset);

  test('maps configured settings into the active currency config', () async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          (ref) async => {
            'currency_symbol': const AppSetting(
              key: 'currency_symbol',
              value: '€',
            ),
            'currency_code': const AppSetting(
              key: 'currency_code',
              value: 'EUR',
            ),
          },
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(settingsProvider.future);
    final config = container.read(currencyConfigProvider);

    expect(config.symbol, '€');
    expect(config.code, 'EUR');
    expect(CurrencyConfigStore.current.symbol, '€');
  });

  test('falls back to defaults when settings are unavailable', () async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          (ref) async => const <String, AppSetting>{},
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(settingsProvider.future);
    final config = container.read(currencyConfigProvider);

    expect(config.symbol, 'Rs.');
    expect(config.code, 'PKR');
  });
}
