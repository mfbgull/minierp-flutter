// Settings screen — PORTING.md §13 (`/settings` → `SettingsScreen`).
//
// A grouped key-value editor over `GET /settings` + `POST /settings/bulk`.
// The server's key store is split into Company / Currency & Formatting /
// Tax / Document-numbering cards (integration keys like `sendgrid_*` and
// `*_api_key` belong to the Integrations module and are hidden here);
// unknown keys fall through to an "Other" card so nothing is ever lost.
//
// Each card saves its changed fields atomically through the bulk endpoint
// and marks itself with an "unsaved" chip while any field differs from the
// loaded server values. Document-numbering counters are editable but
// flagged as server-managed.

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_range_math.dart' show WeekStart;
import '../../data/models/setting.dart' show AppSetting;
import '../../data/repositories/api_result.dart' show ApiError, ApiFailure, ApiSuccess;
import '../../data/repositories/settings_repository.dart'
    show settingsRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/screen_error_panel.dart';
import '../preferences/preference_providers.dart'
    show saveDefaultRange, saveWeekStart, weekStartProvider;
import '../reports/report_providers.dart'
    show globalReportFromDateProvider, globalReportToDateProvider;
import 'settings_providers.dart';

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
                        for (final section in sections) ...[
                          _sectionCard(l10n, section),
                          const SizedBox(height: 16),
                        ],
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

  Widget _sectionCard(AppLocalizations l10n, _Section section) {
    final scheme = Theme.of(context).colorScheme;
    final dirty = _sectionDirty(section);
    final saving = _savingSections.contains(section.id);

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(section.icon, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
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
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      l10n.settingsUnsaved,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: saving || !dirty ? null : () => _saveSection(section),
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 18),
                  label: Text(l10n.commonSave),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final key in section.keys) ...[
              _field(
                key: key,
                helper: _isNumberingKey(key)
                    ? l10n.settingsNumberingHelper
                    : null,
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.date_range_outlined, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.settingsSectionDate,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Week starts on
            Text(
              l10n.drpWeekStartsOn,
              style: Theme.of(context).textTheme.bodyMedium,
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
      ),
    );
  }
}
