import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Locales the app ships — mirrors `supportedLocales` in `app.dart`.
const supportedLocales = [Locale('en'), Locale('ur')];

/// App locale, persisted across sessions. Starts from the system locale
/// when it is one of [supportedLocales], otherwise English.
final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>(
  (ref) => LocaleNotifier(),
);

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(_systemOrEnglish()) {
    _restore();
  }

  static const _prefsKey = 'app_locale';

  static Locale _systemOrEnglish() {
    final system = WidgetsBinding.instance.platformDispatcher.locale;
    for (final supported in supportedLocales) {
      if (supported.languageCode == system.languageCode) return supported;
    }
    return const Locale('en');
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefsKey);
    if (code != null && code != state.languageCode) {
      state = Locale(code);
    }
  }

  /// Switches the app language and persists the choice.
  Future<void> setLocale(Locale locale) async {
    if (!supportedLocales.contains(locale) || locale == state) return;
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, locale.languageCode);
  }
}
