// Unicode TrueType fonts for PDF generation.
//
// dart_pdf's built-in Helvetica faces are Type1 fonts with no Unicode
// support: any non-ASCII glyph renders as a warning and a blank box, and
// the loader prints
//   "Helvetica has no Unicode support see .../Fonts-Management".
// Every PDF document in the app therefore renders with Noto Sans, which is
// declared in pubspec.yaml under `flutter: assets:`.
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// Path of each PDF font face, relative to the pubspec.
class PdfFontAssets {
  static const String regular = 'assets/fonts/NotoSans-Regular.ttf';
  static const String bold = 'assets/fonts/NotoSans-Bold.ttf';
  static const String italic = 'assets/fonts/NotoSans-Italic.ttf';
  static const String boldItalic = 'assets/fonts/NotoSans-BoldItalic.ttf';
}

/// Loads and caches the Noto Sans faces used by every PDF builder.
///
/// Parsing a TTF is a few hundred kilobytes of work, so the results are
/// memoized; calling [theme] from several builders in one print job pays
/// the decode cost once.
class PdfFonts {
  PdfFonts._();

  static pw.Font? _regular;
  static pw.Font? _bold;
  static pw.Font? _italic;
  static pw.Font? _boldItalic;
  static pw.ThemeData? _theme;

  static Future<pw.Font> regular() async =>
      _regular ??= pw.Font.ttf(await rootBundle.load(PdfFontAssets.regular));

  static Future<pw.Font> bold() async =>
      _bold ??= pw.Font.ttf(await rootBundle.load(PdfFontAssets.bold));

  static Future<pw.Font> italic() async =>
      _italic ??= pw.Font.ttf(await rootBundle.load(PdfFontAssets.italic));

  static Future<pw.Font> boldItalic() async => _boldItalic ??=
      pw.Font.ttf(await rootBundle.load(PdfFontAssets.boldItalic));

  /// A [pw.ThemeData] whose default, header, paragraph, bullet, table-header
  /// and table-cell styles all resolve to Noto Sans, with the matching bold
  /// and italic faces so `fontWeight`/`fontStyle` stay real faces rather
  /// than synthetic ones.
  ///
  /// Pass it to `pw.Document(theme: await PdfFonts.theme())`. Individual
  /// `pw.TextStyle`s that do not name a font inherit from this theme, so
  /// no call site needs changing.
  static Future<pw.ThemeData> theme() async => _theme ??= pw.ThemeData.withFont(
        base: await regular(),
        bold: await bold(),
        italic: await italic(),
        boldItalic: await boldItalic(),
      );
}
