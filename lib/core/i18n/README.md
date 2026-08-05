# i18n

Generated localization classes are produced by `flutter gen-l10n`
(auto-run on `pub get`/build because `generate: true` is set in
`pubspec.yaml`).

- Source ARB files: `lib/l10n/en.arb` (812 keys) + `lib/l10n/ur.arb`
  (764 keys) — copied from the kit's `locales/` (PORTING.md §9).
- Generated output: written beside the ARB sources in `lib/l10n/`
  (`app_localizations.dart` + `app_localizations_en.dart` +
  `app_localizations_ur.dart`) — Flutter 3.44 removed the
  `synthetic-package` option, so generation lands in `arb-dir`.
- Note: the kit's original ARB files used invalid ICU `{{count}}` double
  braces; the working copies in `lib/l10n/` were fixed to `{count}`.
- Urdu (ur) is RTL — Flutter handles bidi natively; verify mixed
  number/currency rendering per PORTING.md §9.

Import in widgets:

```dart
import 'l10n/app_localizations.dart';
final l10n = AppLocalizations.of(context)!;
```
