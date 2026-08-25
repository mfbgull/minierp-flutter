// Settings screen — PORTING.md §13 (`/settings` → `SettingsScreen`).
//
// A grouped key-value editor over `GET /settings` + `POST /settings/bulk`.
// The server's key store is split into Company / Currency & Formatting /
// Tax / Document-numbering cards (integration keys like `sendgrid_*` and
// `*_api_key` belong to the Integrations module and are hidden here);
// unknown keys fall through to an "Other" card so nothing is ever lost.
//
// Every section is a collapsible card (ExpansionTile) that starts
// collapsed. Each key-section saves its changed fields atomically
// through the bulk endpoint and marks itself with an "unsaved" chip
// while any field differs from the loaded server values.
// Document-numbering counters are editable but flagged as server-managed.
// The Database Backup card talks to `GET/POST/DELETE /admin/backup`
// (server/src/routes/adminBackup.ts): status, on-demand backup,
// per-file download / delete.

import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/utils/date_range_math.dart' show WeekStart;
import '../../data/models/backup.dart' show BackupFile, BackupStatus;
import '../../data/models/setting.dart' show AppSetting;
import '../../data/repositories/api_result.dart'
    show ApiError, ApiFailure, ApiResult, ApiSuccess;
import '../../data/repositories/backup_repository.dart'
    show backupRepositoryProvider;
import '../../data/repositories/settings_repository.dart'
    show settingsRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/confirm_dialog.dart' show showConfirmDialog;
import '../../widgets/screen_error_panel.dart';
import '../preferences/preference_providers.dart'
    show saveDefaultRange, saveWeekStart, weekStartProvider;
import '../reports/report_providers.dart'
    show globalReportFromDateProvider, globalReportToDateProvider;
import 'settings_providers.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

/// Keys configured on the Integrations module's service forms — excluded
/// here to avoid two editing surfaces for the same store (PORTING.md §13
/// keeps settings to company / tax / numbering).
const _integrationKeys = <String>{
  'sendgrid_enabled',
  'sendgrid_api_key',
  'sendgrid_from_email',
  'sendgrid_from_name',
  'twilio_enabled',
  'twilio_account_sid',
  'twilio_auth_token',
  'twilio_phone_number',
  'weather_enabled',
  'weather_api_key',
  'weather_default_location',
  'validation_enabled',
  'validation_api_key',
  'currency_enabled',
  'currency_api_key',
  'currency_base',
  'currency_rates_update_interval',
  'tax_enabled',
  'tax_api_key',
  'tax_default_country',
  'tax_zip_code',
};

const _companyKeys = <String>[
  'company_name',
  'company_email',
  'company_phone',
  'company_address',
  'company_tax_id',
];

const _currencyKeys = <String>[
  'currency_symbol',
  'currency_code',
  'currency',
  'decimal_places',
  'date_format',
  'tooltip_timeout',
];

const _taxKeys = <String>['tax_rate'];

/// Server-managed counters, e.g. `STK_last_no_2026` / `PAY_last_no`.
bool _isNumberingKey(String key) =>
    key.endsWith('_last_no') || RegExp(r'_last_no_\d{4}$').hasMatch(key);

class _Section {
  const _Section({
    required this.id,
    required this.icon,
    required this.keys,
  });

  final String id;
  final IconData icon;
  final List<String> keys;
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Map<String, TextEditingController> _controllers = {};
  Map<String, String> _serverTruth = {};
  final Set<String> _savingSections = {};

  // Database Backup card state. `null` means "never loaded" — the list
  // is fetched lazily on first expansion of the card.
  ApiResult<BackupStatus>? _backups;
  bool _backupsLoading = false;
  bool _creatingBackup = false;
  final Set<String> _downloadingFiles = {};
  final Set<String> _deletingFiles = {};

  BackupStatus? get _backupData => switch (_backups) {
    ApiSuccess<BackupStatus>(:final data) => data,
    _ => null,
  };

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Syncs the editor with freshly-loaded server data. Called during build
  /// whenever the provider yields values that differ from the snapshot the
  /// controllers were last initialised from — first load, a manual refresh,
  /// or an external change. Local edits are preserved when the incoming
  /// data matches the last snapshot (e.g. after a save round-trip).
  void _syncFromServer(Map<String, AppSetting> settings) {
    final incoming = {
      for (final entry in settings.entries) entry.key: entry.value.value,
    };
    if (mapEquals(incoming, _serverTruth)) return;
    final old = _controllers;
    final next = <String, TextEditingController>{};
    for (final entry in settings.entries) {
      final controller = TextEditingController(text: entry.value.value);
      // Rebuild on edits so the card's unsaved chip + Save button react
      // live (a plain rebuild only happens when the provider changes).
      controller.addListener(_onFieldChanged);
      next[entry.key] = controller;
    }
    _controllers = next;
    _serverTruth = incoming;
    // The previously-mounted TextFormFields still reference the old
    // controllers until this build completes — dispose them after the
    // frame (disposing during build would trip a "used after being
    // disposed" assertion when the field elements swap controllers).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in old.values) {
        controller.dispose();
      }
    });
  }

  /// Marks the screen dirty whenever any field's text changes so the
  /// unsaved chip / Save button track live edits.
  void _onFieldChanged() {
    if (!mounted) return;
    setState(() {});
  }

  List<_Section> _buildSections(Iterable<String> keys) {
    final known = <String>[
      ..._companyKeys,
      ..._currencyKeys,
      ..._taxKeys,
    ];
    final numbering = [
      for (final key in keys)
        if (_isNumberingKey(key) && !_integrationKeys.contains(key)) key,
    ];
    final other = [
      for (final key in keys)
        if (!known.contains(key) &&
            !_integrationKeys.contains(key) &&
            !_isNumberingKey(key))
          key,
    ];
    return [
      if (keys.any(_companyKeys.contains))
        const _Section(
          id: 'company',
          icon: Icons.business_outlined,
          keys: _companyKeys,
        ),
      if (keys.any(_currencyKeys.contains))
        const _Section(
          id: 'currency',
          icon: Icons.currency_exchange_outlined,
          keys: _currencyKeys,
        ),
      if (keys.any(_taxKeys.contains))
        const _Section(id: 'tax', icon: Icons.percent_outlined, keys: _taxKeys),
      if (numbering.isNotEmpty)
        _Section(
          id: 'numbering',
          icon: Icons.tag_outlined,
          keys: numbering,
        ),
      if (other.isNotEmpty)
        _Section(
          id: 'other',
          icon: Icons.tune_outlined,
          keys: other,
        ),
    ];
  }

  bool _sectionDirty(_Section section) => section.keys.any(
    (key) =>
        _controllers[key] != null &&
        _controllers[key]!.text != _serverTruth[key],
  );

  Future<void> _saveSection(_Section section) async {
    if (_savingSections.contains(section.id)) return;
    final l10n = AppLocalizations.of(context)!;
    final changed = <String, String>{
      for (final key in section.keys)
        if (_controllers[key] != null &&
            _controllers[key]!.text != _serverTruth[key])
          key: _controllers[key]!.text,
    };
    if (changed.isEmpty) return;

    setState(() => _savingSections.add(section.id));
    final result = await ref
        .read(settingsRepositoryProvider)
        .updateBulk(changed);
    if (!mounted) return;
    setState(() => _savingSections.remove(section.id));

    switch (result) {
      case ApiSuccess(:final data):
        // The bulk response is the refreshed store — adopt it as the new
        // server truth so the unsaved chips clear (controllers already hold
        // the saved text).
        setState(() {
          _serverTruth = {
            for (final entry in data.entries) entry.key: entry.value.value,
          };
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.settingsSaved)));
      case ApiFailure(:final error):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_saveError(l10n, error))));
    }
  }

  String _saveError(AppLocalizations l10n, ApiError error) {
    if (error.isNetwork) return l10n.settingsSaveFailed;
    return error.message.isEmpty ? l10n.settingsSaveFailed : error.message;
  }

  String _labelFor(AppLocalizations l10n, String key) => switch (key) {
    'company_name' => l10n.settingsKeyCompanyName,
    'company_email' => l10n.settingsKeyCompanyEmail,
    'company_phone' => l10n.settingsKeyCompanyPhone,
    'company_address' => l10n.settingsKeyCompanyAddress,
    'company_tax_id' => l10n.settingsKeyCompanyTaxId,
    'currency_symbol' => l10n.settingsKeyCurrencySymbol,
    'currency_code' => l10n.settingsKeyCurrencyCode,
    'currency' => l10n.settingsKeyCurrency,
    'decimal_places' => l10n.settingsKeyDecimalPlaces,
    'date_format' => l10n.settingsKeyDateFormat,
    'tooltip_timeout' => l10n.settingsKeyTooltipTimeout,
    'tax_rate' => l10n.settingsKeyTaxRate,
    _ => _humanize(key),
  };

  static String _humanize(String key) => key
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  String _sectionTitle(AppLocalizations l10n, _Section section) =>
      switch (section.id) {
        'company' => l10n.settingsSectionCompany,
        'currency' => l10n.settingsSectionCurrency,
        'tax' => l10n.settingsSectionTax,
        'numbering' => l10n.settingsSectionNumbering,
        _ => l10n.settingsSectionOther,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider);

    return settings.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ScreenErrorPanel(
        message: error is ApiError ? error.message : '$error',
        onRetry: () => ref.invalidate(settingsProvider),
      ),
      data: (map) {
        _syncFromServer(map);
        if (map.isEmpty) {
          return Center(child: Text(l10n.settingsEmpty));
        }
        final sections = _buildSections(map.keys);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.settingsSubtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.commonRefresh,
                    icon: const Icon(Icons.refresh),
                    onPressed: () => ref.invalidate(settingsProvider),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      children: [
                        _dateRangeSection(l10n),
                        const SizedBox(height: 16),
                        _backupSection(l10n),
                        const SizedBox(height: 16),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final w = constraints.maxWidth;
                            final cols = w >= 768 ? 3 : (w >= 520 ? 2 : 1);
                            final cardW = (w - (cols - 1) * 16) / cols;
                            return Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              alignment: WrapAlignment.center,
                              children: [
                                for (final section in sections)
                                  SizedBox(
                                    width: cardW,
                                    child: _sectionCard(l10n, section),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Collapsible key-section card — starts collapsed; the unsaved chip
  /// stays visible in the header while collapsed, fields + Save button
  /// live in the expanded children.
  Widget _sectionCard(AppLocalizations l10n, _Section section) {
    final scheme = Theme.of(context).colorScheme;
    final dirty = _sectionDirty(section);
    final saving = _savingSections.contains(section.id);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.mdRadius,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(section.icon, size: 20, color: scheme.primary),
        initiallyExpanded: false,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          children: [
            Expanded(
              child: Text(
                _sectionTitle(l10n, section),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (dirty && !saving)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  borderRadius: AppBorderRadius.badge,
                ),
                child: Text(
                  l10n.settingsUnsaved,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ),
          ],
        ),
        children: [
          for (final key in section.keys) ...[
            _field(
              key: key,
              helper: _isNumberingKey(key)
                  ? l10n.settingsNumberingHelper
                  : null,
            ),
            const SizedBox(height: 12),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed:
                  saving || !dirty ? null : () => _saveSection(section),
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(l10n.commonSave),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({required String key, String? helper}) {
    final l10n = AppLocalizations.of(context)!;
    final description = ref
        .read(settingsProvider)
        .valueOrNull?[key]
        ?.description; // may be null for numbering counters
    return TextFormField(
      controller: _controllers[key],
      decoration: InputDecoration(
        labelText: _labelFor(l10n, key),
        helperText: helper ?? description,
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  // ── Date & Range section (§5.1 / spec §6.4) ──────────────────────────
  Widget _dateRangeSection(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final currentWeekStart = ref.watch(weekStartProvider);
    // Read the *current active* range from the global report providers —
    // this is what the user sees on the dashboard / reports right now.
    final fromDate = ref.watch(globalReportFromDateProvider);
    final toDate = ref.watch(globalReportToDateProvider);
    final hasActiveRange = fromDate != null && toDate != null;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.mdRadius,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(Icons.date_range_outlined, size: 20, color: scheme.primary),
        initiallyExpanded: false,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text(
          l10n.settingsSectionDate,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        children: [
          // Week starts on
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.drpWeekStartsOn,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<WeekStart>(
            segments: [
              ButtonSegment(
                value: WeekStart.monday,
                label: Text(l10n.drpWeekdayMonday),
              ),
              ButtonSegment(
                value: WeekStart.saturday,
                label: Text(l10n.drpWeekdaySaturday),
              ),
              ButtonSegment(
                value: WeekStart.sunday,
                label: Text(l10n.drpWeekdaySunday),
              ),
            ],
            selected: {currentWeekStart},
            onSelectionChanged: (selection) {
              final value = selection.first;
              ref.read(weekStartProvider.notifier).state = value;
              saveWeekStart(ref, value).then((error) {
                if (!mounted || error == null) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.drpWeekStartFailed)),
                );
              });
            },
          ),
          const SizedBox(height: 16),
          // Set current range as default — captures the active range
          // from the dashboard / reports and persists it as the default
          // for next app open (spec §6.2).
          Row(
            children: [
              Icon(
                Icons.bookmark_outline,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.drpSetDefault,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: !hasActiveRange
                    ? null
                    : () async {
                        final error = await saveDefaultRange(
                          ref,
                          (from: fromDate, to: toDate),
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              error == null
                                  ? l10n.drpDefaultSet
                                  : l10n.drpDefaultFailed,
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: Text(l10n.drpSetDefault),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Database Backup section (/admin/backup) ──────────────────────────
  Widget _backupSection(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.mdRadius,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(Icons.backup_outlined, size: 20, color: scheme.primary),
        initiallyExpanded: false,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text(
          l10n.settingsSectionBackup,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        onExpansionChanged: (expanded) {
          if (expanded && _backups == null) _loadBackups();
        },
        children: [
          _backupStatusRow(l10n),
          const SizedBox(height: 12),
          _createBackupRow(l10n),
          const SizedBox(height: 12),
          _backupFilesList(l10n),
        ],
      ),
    );
  }

  Widget _backupStatusRow(AppLocalizations l10n) {
    final status = _backupData;
    final lastAt = status?.lastBackupAt;
    return Row(
      children: [
        Expanded(
          child: Text(
            '${l10n.settingsBackupLast}: ${lastAt == null ? l10n.settingsBackupNever : _formatDateTime(lastAt)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        IconButton(
          tooltip: l10n.commonRefresh,
          icon: _backupsLoading && status != null
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 20),
          onPressed: _backupsLoading ? null : _loadBackups,
        ),
      ],
    );
  }

  Widget _createBackupRow(AppLocalizations l10n) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.tonalIcon(
        onPressed: _creatingBackup ? null : _createBackup,
        icon: _creatingBackup
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.backup_outlined, size: 18),
        label: Text(l10n.settingsBackupNow),
      ),
    );
  }

  Widget _backupFilesList(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final status = _backupData;

    if (_backupsLoading && status == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final error = switch (_backups) {
      ApiFailure(:final error) => error,
      _ => null,
    };
    if (status == null && error != null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              error.message.isEmpty ? l10n.settingsBackupFailed : error.message,
              style: TextStyle(color: scheme.error),
            ),
          ),
          TextButton(
            onPressed: _backupsLoading ? null : _loadBackups,
            child: Text(l10n.commonRefresh),
          ),
        ],
      );
    }
    final files = status?.backups ?? const <BackupFile>[];
    if (files.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          l10n.settingsBackupEmpty,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            l10n.settingsBackupFiles,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        const SizedBox(height: 4),
        for (final file in files) _backupFileRow(l10n, file),
      ],
    );
  }

  /// One backup file row — auxiliary list inside a card, not a primary
  /// data grid, so no PlutoGrid here.
  Widget _backupFileRow(AppLocalizations l10n, BackupFile file) {
    final scheme = Theme.of(context).colorScheme;
    final downloading = _downloadingFiles.contains(file.name);
    final deleting = _deletingFiles.contains(file.name);
    final busy = downloading || deleting;

    Widget actionIcon(IconData icon, bool spinning) => spinning
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon, size: 20);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.description_outlined,
              size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  '${_formatBytes(file.sizeBytes)} · ${_formatDateTime(file.createdAt)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.commonDownload,
            onPressed: busy ? null : () => _downloadBackup(file),
            icon: actionIcon(Icons.download_outlined, downloading),
          ),
          IconButton(
            tooltip: l10n.commonDelete,
            onPressed: busy ? null : () => _deleteBackup(file),
            icon: actionIcon(Icons.delete_outline, deleting),
          ),
        ],
      ),
    );
  }

  Future<void> _loadBackups() async {
    if (_backupsLoading) return;
    setState(() => _backupsLoading = true);
    final result = await ref.read(backupRepositoryProvider).status();
    if (!mounted) return;
    setState(() {
      _backups = result;
      _backupsLoading = false;
    });
  }

  Future<void> _createBackup() async {
    if (_creatingBackup) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _creatingBackup = true);
    final result = await ref.read(backupRepositoryProvider).create();
    if (!mounted) return;
    setState(() => _creatingBackup = false);
    _showSnack(switch (result) {
      ApiSuccess() => l10n.settingsBackupSuccess,
      ApiFailure(:final error) => error.message.isEmpty
          ? l10n.settingsBackupFailed
          : error.message,
    });
    if (result is ApiSuccess<String>) _loadBackups();
  }

  Future<void> _downloadBackup(BackupFile file) async {
    if (_downloadingFiles.contains(file.name)) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _downloadingFiles.add(file.name));
    try {
      final result =
          await ref.read(backupRepositoryProvider).downloadBytes(file.name);
      if (!mounted) return;
      await result.fold<Future<void>>(onSuccess: (bytes) async {
        try {
          final path = await FilePicker.saveFile(
            dialogTitle: file.name,
            fileName: file.name,
            bytes: bytes,
          );
          if (path == null || !mounted) return; // dialog cancelled
          await File(path).writeAsBytes(bytes, flush: true);
          if (!mounted) return;
          _showSnack(l10n.settingsBackupDownloaded);
        } catch (_) {
          if (mounted) _showSnack(l10n.settingsBackupDownloadFailed);
        }
      }, onFailure: (error) async {
        _showSnack(error.message.isEmpty
            ? l10n.settingsBackupDownloadFailed
            : error.message);
      });
    } finally {
      if (mounted) setState(() => _downloadingFiles.remove(file.name));
    }
  }

  Future<void> _deleteBackup(BackupFile file) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.settingsBackupDeleteTitle,
      message: l10n.settingsBackupDeleteMessage,
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    if (_deletingFiles.contains(file.name)) return;
    setState(() => _deletingFiles.add(file.name));
    final result = await ref.read(backupRepositoryProvider).delete(file.name);
    if (!mounted) return;
    setState(() => _deletingFiles.remove(file.name));
    _showSnack(switch (result) {
      ApiSuccess() => l10n.settingsBackupDeleted,
      ApiFailure(:final error) => error.message.isEmpty
          ? l10n.settingsBackupDeleteFailed
          : error.message,
    });
    if (result is ApiSuccess<void>) _loadBackups();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _formatDateTime(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    return DateFormat('yyyy-MM-dd HH:mm').format(parsed);
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}
