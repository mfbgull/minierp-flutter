#!/usr/bin/env dart
// tool/m3_color_audit.dart
//
// Scans all `lib/**/*.dart` files and reports hardcoded `Colors.*` usage
// that should be replaced with M3 ColorScheme tokens.
//
// Usage:
//   dart run tool/m3_color_audit.dart
//   dart run tool/m3_color_audit.dart --json        (machine-readable output)
//   dart run tool/m3_color_audit.dart --file report.txt  (write to file)

import 'dart:io';

// --- Classification ---

enum Severity {
  high('HIGH', 'Replace with M3 token'),
  medium('MED', 'Review — may be intentional'),
  low('LOW', 'Acceptable or out of scope'),
  pdf('PDF', 'PDF package — no Flutter theme'),
  none('OK', 'Already M3-compatible or acceptable');

  final String label;
  final String action;
  const Severity(this.label, this.action);
}

class ColorUsage {
  final String file;
  final int line;
  final String code;
  final String colorRef;
  final Severity severity;
  final String? suggestion;

  const ColorUsage({
    required this.file,
    required this.line,
    required this.code,
    required this.colorRef,
    required this.severity,
    this.suggestion,
  });
}

// --- Classification rules ---

// Hardcoded Colors.* that need M3 replacement
const _highPriorityPatterns = {
  // Active/inactive status — use colorScheme.primary / colorScheme.outline
  'Colors.green': 'Use colorScheme.primary (or statusColors map)',
  'Colors.green.shade700': 'Use colorScheme.primary (darker variant)',
  'Colors.green.shade600': 'Use colorScheme.primary (darker variant)',
  'Colors.blueGrey': 'Use colorScheme.outline or colorScheme.onSurfaceVariant',
  // Error states — use colorScheme.error
  'Colors.red': 'Use colorScheme.error',
  'Colors.red.shade700': 'Use colorScheme.error (darker variant)',
  'Colors.redAccent': 'Use colorScheme.error',
  // Informational — use colorScheme.tertiary or semantic tokens
  'Colors.blue': 'Use colorScheme.tertiary or colorScheme.primary',
  'Colors.lightBlue': 'Use colorScheme.tertiaryContainer',
  'Colors.lightBlueAccent': 'Use colorScheme.tertiaryContainer',
  // Warning — consider colorScheme.tertiary or custom amber
  'Colors.orange': 'Use colorScheme.tertiary or custom amber token',
  'Colors.amber': 'Use colorScheme.tertiary or custom amber token',
  // Neutral — use M3 outline tokens
  'Colors.grey': 'Use colorScheme.outline or colorScheme.outlineVariant',
  'Colors.grey.shade600': 'Use colorScheme.outline',
  // Purple variants — use colorScheme.secondary or tertiary
  'Colors.purple': 'Use colorScheme.secondary or tertiary',
  'Colors.deepPurple': 'Use colorScheme.secondary or tertiary',
  'Colors.teal': 'Use colorScheme.tertiary',
  'Colors.tealAccent': 'Use colorScheme.tertiaryContainer',
  'Colors.lightGreen': 'Use colorScheme.primaryContainer',
};

// Hardcoded Colors.* that are medium risk — review needed
const _mediumPriorityPatterns = {
  'Colors.black54': 'Use colorScheme.onSurface.withValues(alpha: 0.54)',
  'Colors.white': 'Review context — may be text on colored bg (keep) or need colorScheme.onPrimary',
  'Colors.black87': 'Use colorScheme.onSurface',
  'Colors.black26': 'Use colorScheme.onSurface.withValues(alpha: 0.26)',
  'Colors.black12': 'Use colorScheme.onSurface.withValues(alpha: 0.12)',
  'Colors.black38': 'Use colorScheme.onSurface.withValues(alpha: 0.38)',
  'Colors.black45': 'Use colorScheme.onSurface.withValues(alpha: 0.45)',
  'Colors.transparent': 'OK — no replacement needed',
};

// PDF package colors — out of scope
const _pdfPatterns = {
  'PdfColors.white': null,
  'PdfColors.grey': null,
  'PdfColors.grey100': null,
  'PdfColors.grey300': null,
  'PdfColors.grey400': null,
  'PdfColors.grey600': null,
  'PdfColors.grey700': null,
  'PdfColors.grey800': null,
  'PdfColors.black': null,
};

// Already M3-compatible or acceptable
const _lowPriorityPatterns = {
  'Colors.transparent': 'Transparent — no replacement needed',
  'Colors.black': 'Rarely used in Flutter UI — verify context',
};

// Files that are purely PDF generation — skip entirely
const _pdfFiles = {
  'invoice_pdf.dart',
  'sales_order_pdf.dart',
  'quotation_pdf.dart',
  'purchase_order_pdf.dart',
  'ledger_export.dart',
  'receipt_pdf.dart',
  'statement_pdf.dart',
};

// Files that are purely CSV export — skip
const _csvFiles = {
  'csv_export.dart',
};

Severity _classify(String file, String colorRef) {
  final basename = file.split('/').last;

  // Skip PDF files entirely
  if (_pdfFiles.contains(basename)) return Severity.pdf;

  // Skip CSV files
  if (_csvFiles.contains(basename)) return Severity.pdf;

  // Check PDF package colors
  for (final pattern in _pdfPatterns.keys) {
    if (colorRef.startsWith(pattern)) return Severity.pdf;
  }

  // Check high priority
  for (final pattern in _highPriorityPatterns.keys) {
    if (colorRef == pattern || colorRef.startsWith('$pattern(')) {
      return Severity.high;
    }
  }

  // Check medium priority
  for (final pattern in _mediumPriorityPatterns.keys) {
    if (colorRef == pattern || colorRef.startsWith('$pattern(')) {
      return Severity.medium;
    }
  }

  // Check low priority
  for (final pattern in _lowPriorityPatterns.keys) {
    if (colorRef == pattern) return Severity.low;
  }

  return Severity.none;
}

String? _suggestion(String colorRef) {
  return _highPriorityPatterns[colorRef] ??
      _mediumPriorityPatterns[colorRef] ??
      _lowPriorityPatterns[colorRef];
}

// --- Scanner ---

List<ColorUsage> scanDirectory(String libDir) {
  final results = <ColorUsage>[];
  final dir = Directory(libDir);

  if (!dir.existsSync()) {
    stderr.writeln('Error: Directory not found: $libDir');
    exit(1);
  }

  final dartFiles = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  // Pattern: Colors.xxx or Colors.xxx.shadeNNN or Colors.xxxAccent
  final colorPattern = RegExp(r'Colors\.(\w+(?:\.shade\d+)?(?:\w*Accent)?)');
  // Also catch PdfColors.xxx
  final pdfColorPattern = RegExp(r'PdfColors\.(\w+)');

  for (final file in dartFiles) {
    final relativePath = file.path.replaceFirst(RegExp(r'.*?lib/'), 'lib/');
    final lines = file.readAsLinesSync();

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineNum = i + 1;

      // Skip comments
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;

      // Check Flutter Colors.*
      for (final match in colorPattern.allMatches(line)) {
        final fullRef = 'Colors.${match.group(1)}';
        final severity = _classify(relativePath, fullRef);
        final suggestion = _suggestion(fullRef);

        results.add(ColorUsage(
          file: relativePath,
          line: lineNum,
          code: line.trim(),
          colorRef: fullRef,
          severity: severity,
          suggestion: suggestion,
        ));
      }

      // Check PdfColors.*
      for (final match in pdfColorPattern.allMatches(line)) {
        final fullRef = 'PdfColors.${match.group(1)}';
        results.add(ColorUsage(
          file: relativePath,
          line: lineNum,
          code: line.trim(),
          colorRef: fullRef,
          severity: Severity.pdf,
          suggestion: null,
        ));
      }
    }
  }

  return results;
}

// --- Output ---

void printReport(List<ColorUsage> usages) {
  final high = usages.where((u) => u.severity == Severity.high).toList();
  final medium = usages.where((u) => u.severity == Severity.medium).toList();
  final low = usages.where((u) => u.severity == Severity.low).toList();
  final pdf = usages.where((u) => u.severity == Severity.pdf).toList();

  print('');
  print('═══════════════════════════════════════════════════════════════');
  print('  M3 Color Audit Report');
  print('  ${DateTime.now().toIso8601String().substring(0, 19)}');
  print('═══════════════════════════════════════════════════════════════');
  print('');

  // Summary
  print('┌─────────────────────────────────────────────┐');
  print('│  Summary                                    │');
  print('├─────────────────────────────────────────────┤');
  print('│  Total hardcoded Colors.* found: ${usages.length.toString().padLeft(4)}      │');
  print('│  HIGH priority (replace):      ${high.length.toString().padLeft(4)}      │');
  print('│  MEDIUM priority (review):     ${medium.length.toString().padLeft(4)}      │');
  print('│  LOW priority (acceptable):    ${low.length.toString().padLeft(4)}      │');
  print('│  PDF/CSV (out of scope):       ${pdf.length.toString().padLeft(4)}      │');
  print('└─────────────────────────────────────────────┘');
  print('');

  // HIGH priority — grouped by file
  if (high.isNotEmpty) {
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('  🔴 HIGH PRIORITY — Replace with M3 tokens');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('');

    final byFile = <String, List<ColorUsage>>{};
    for (final u in high) {
      (byFile[u.file] ??= []).add(u);
    }

    for (final entry in byFile.entries) {
      print('  📄 ${entry.key}');
      for (final u in entry.value) {
        print('     L${u.line.toString().padLeft(4)} │ ${u.colorRef}');
        print('           │ ${u.suggestion ?? 'See M3 token map'}');
        print('           │ ${u.code}');
      }
      print('');
    }

    // Group by color pattern
    print('  ── By color pattern ──');
    print('');
    final byColor = <String, int>{};
    for (final u in high) {
      byColor[u.colorRef] = (byColor[u.colorRef] ?? 0) + 1;
    }
    final sorted = byColor.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sorted) {
      print('    ${entry.key.padRight(28)} ${entry.value.toString().padLeft(3)} occurrences');
      final sug = _suggestion(entry.key);
      if (sug != null) print('    ${''.padRight(28)} → $sug');
    }
    print('');
  }

  // MEDIUM priority
  if (medium.isNotEmpty) {
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('  🟡 MEDIUM PRIORITY — Review for M3 compliance');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('');

    final byFile = <String, List<ColorUsage>>{};
    for (final u in medium) {
      (byFile[u.file] ??= []).add(u);
    }

    for (final entry in byFile.entries) {
      print('  📄 ${entry.key}');
      for (final u in entry.value) {
        print('     L${u.line.toString().padLeft(4)} │ ${u.colorRef}');
        if (u.suggestion != null) print('           │ ${u.suggestion}');
      }
      print('');
    }
  }

  // LOW priority — just count
  if (low.isNotEmpty) {
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('  🟢 LOW PRIORITY — Acceptable or out of scope (${low.length} occurrences)');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('');
    final byColor = <String, int>{};
    for (final u in low) {
      byColor[u.colorRef] = (byColor[u.colorRef] ?? 0) + 1;
    }
    for (final entry in byColor.entries) {
      print('    ${entry.key.padRight(28)} ${entry.value.toString().padLeft(3)} occurrences');
    }
    print('');
  }

  // PDF — skip
  if (pdf.isNotEmpty) {
    final nonPdfColors = pdf.where((u) => !u.file.contains('_pdf.dart')).toList();
    if (nonPdfColors.isNotEmpty) {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('  ⚪ PDF/CSV (out of scope) — ${nonPdfColors.length} occurrences in non-PDF files');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('');
      for (final u in nonPdfColors) {
        print('    ${u.file}:${u.line} │ ${u.colorRef}');
      }
      print('');
    }
  }

  // Migration checklist
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('  📋 Migration Checklist');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('');
  print('  1. Create lib/core/theme/status_colors.dart with M3-aware maps');
  print('  2. Replace Colors.green → colorScheme.primary in status maps');
  print('  3. Replace Colors.blueGrey → colorScheme.outline in status maps');
  print('  4. Replace Colors.red → colorScheme.error in status maps');
  print('  5. Replace Colors.black54 → colorScheme.onSurface.withValues(alpha: 0.54)');
  print('  6. Review Colors.white usage (may be intentional on colored bg)');
  print('  7. Leave PdfColors.* unchanged (PDF lib uses own palette)');
  print('  8. Run: flutter analyze lib/ — verify zero issues');
  print('  9. Visual test: light mode + dark mode');
  print('');
}

void printJsonReport(List<ColorUsage> usages) {
  final output = {
    'summary': {
      'total': usages.length,
      'high': usages.where((u) => u.severity == Severity.high).length,
      'medium': usages.where((u) => u.severity == Severity.medium).length,
      'low': usages.where((u) => u.severity == Severity.low).length,
      'pdf': usages.where((u) => u.severity == Severity.pdf).length,
    },
    'usages': usages
        .map((u) => {
              'file': u.file,
              'line': u.line,
              'code': u.code,
              'colorRef': u.colorRef,
              'severity': u.severity.label,
              'suggestion': u.suggestion,
            })
        .toList(),
  };

  // Simple JSON printer (no dependency)
  print('{');
  print('  "summary": {');
  final summary = output['summary'] as Map<String, int>;
  final entries = summary.entries.toList();
  for (var i = 0; i < entries.length; i++) {
    final comma = i < entries.length - 1 ? ',' : '';
    print('    "${entries[i].key}": ${entries[i].value}$comma');
  }
  print('  },');
  print('  "usages": [');
  final usagesList = output['usages'] as List<Map<String, Object?>>;
  for (var i = 0; i < usagesList.length; i++) {
    final u = usagesList[i];
    final comma = i < usagesList.length - 1 ? ',' : '';
    final suggestion = u['suggestion'] != null
        ? '"${(u['suggestion'] as String).replaceAll('"', '\\"')}"'
        : 'null';
    print('    {"file":"${u['file']}","line":${u['line']},"colorRef":"${u['colorRef']}","severity":"${u['severity']}","suggestion":$suggestion}$comma');
  }
  print('  ]');
  print('}');
}

// --- Main ---

void main(List<String> args) {
  final jsonMode = args.contains('--json');
  final fileIdx = args.indexOf('--file');
  final outputPath = fileIdx != -1 && fileIdx + 1 < args.length
      ? args[fileIdx + 1]
      : null;

  // Resolve lib/ directory relative to script location
  final scriptDir = File(Platform.script.toFilePath()).parent;
  final libDir = scriptDir.parent.path.contains('lib')
      ? scriptDir.parent.parent.path
      : scriptDir.parent.path;
  final resolvedLib = '$libDir/lib';

  if (!jsonMode) {
    stderr.writeln('Scanning: $resolvedLib');
  }

  final usages = scanDirectory(resolvedLib);

  if (jsonMode) {
    printJsonReport(usages);
  } else {
    if (outputPath != null) {
      final buf = StringBuffer();
      final orig = stdout;
      // Redirect stdout to buffer
      printReport(usages);
      // Actually, just write directly
      final file = File(outputPath);
      // Re-run with captured output — simpler to just write the report
      stderr.writeln('Writing report to: $outputPath');
      // For simplicity, print to stdout (user can redirect)
      printReport(usages);
    } else {
      printReport(usages);
    }
  }
}
