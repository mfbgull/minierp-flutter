// Integrations screen — PORTING.md §13 (`/integrations` →
// `IntegrationsScreen`, admin-only). One card per third-party service
// (email/notifications/weather/validation/currency/tax) over
// `GET /integrations/settings` + `PUT /integrations/settings/:service`.
//
// The server only reports `enabled`/`configured` per service — keys are
// encrypted and never returned — so each card's key fields start blank
// and are sent only when typed. The enabled switch reflects the loaded
// status; saving a card PUTs `{enabled, …non-blank fields}` and refreshes
// the status strip.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/api_result.dart'
    show ApiError, ApiFailure, ApiSuccess;
import '../../l10n/app_localizations.dart';
import '../../widgets/screen_error_panel.dart';
import 'integration_models.dart';
import 'integrations_providers.dart';
import 'integrations_repository.dart' show integrationsRepositoryProvider;
import 'package:minierp_app/core/theme/app_border_radius.dart';

class IntegrationsScreen extends ConsumerWidget {
  const IntegrationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final status = ref.watch(integrationsStatusProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.integrationsSubtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.commonRefresh,
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(integrationsStatusProvider),
              ),
            ],
          ),
        ),
        Expanded(
          child: status.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ScreenErrorPanel(
              message: error is ApiError ? error.message : '$error',
              onRetry: () => ref.invalidate(integrationsStatusProvider),
            ),
            data: (map) => map.isEmpty
                ? Center(
                    child: Text(
                      l10n.commonNodata,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: Column(
                          children: [
                            for (final service in integrationServices) ...[
                              _ServiceCard(
                                service: service,
                                status: map[service.id],
                              ),
                              const SizedBox(height: 16),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ServiceCard extends ConsumerStatefulWidget {
  const _ServiceCard({required this.service, required this.status});

  final IntegrationService service;

  /// May be null when the server doesn't report this service.
  final IntegrationServiceStatus? status;

  @override
  ConsumerState<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends ConsumerState<_ServiceCard> {
  bool _enabled = false;
  late final Map<String, TextEditingController> _controllers;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _enabled = widget.status?.enabled ?? false;
    _controllers = {
      for (final field in widget.service.fields)
        field.bodyKey: TextEditingController(),
    };
  }

  @override
  void didUpdateWidget(_ServiceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The status strip refreshed after a save — adopt the new enabled
    // flag without clobbering the user's in-progress field edits.
    if (widget.status?.enabled != oldWidget.status?.enabled) {
      _enabled = widget.status?.enabled ?? false;
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// A card is dirty when the toggle differs from the server, or any key
  /// field has text (keys are never prefilled, so any text is new).
  bool get _dirty =>
      _enabled != (widget.status?.enabled ?? false) ||
      _controllers.values.any((c) => c.text.isNotEmpty);

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context)!;
    final body = <String, dynamic>{
      'enabled': _enabled,
      // Only non-blank fields are sent — the server treats an absent
      // `apiKey` as "keep the stored key" (it never returns one).
      for (final field in widget.service.fields)
        if (_controllers[field.bodyKey]!.text.isNotEmpty)
          field.bodyKey: _controllers[field.bodyKey]!.text,
    };

    setState(() => _saving = true);
    final result = await ref
        .read(integrationsRepositoryProvider)
        .updateService(widget.service.id, body);
    if (!mounted) return;
    setState(() => _saving = false);

    switch (result) {
      case ApiSuccess():
        for (final controller in _controllers.values) {
          controller.clear();
        }
        setState(() {});
        ref.invalidate(integrationsStatusProvider);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.integrationsSaved)));
      case ApiFailure(:final error):
        final message = error.isNetwork
            ? l10n.integrationsSaveFailed
            : error.message.isEmpty
            ? l10n.integrationsSaveFailed
            : error.message;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _title(AppLocalizations l10n) => switch (widget.service.id) {
    'email' => l10n.integrationsServiceEmail,
    'notifications' => l10n.integrationsServiceNotifications,
    'weather' => l10n.integrationsServiceWeather,
    'validation' => l10n.integrationsServiceValidation,
    'currency' => l10n.integrationsServiceCurrency,
    _ => l10n.integrationsServiceTax,
  };

  String _fieldLabel(AppLocalizations l10n, String bodyKey) =>
      switch (bodyKey) {
        'apiKey' => l10n.integrationsApikey,
        'from_email' => l10n.integrationsFieldFromemail,
        'from_name' => l10n.integrationsFieldFromname,
        'account_sid' => l10n.integrationsFieldAccountsid,
        'phone_number' => l10n.integrationsFieldPhonenumber,
        'default_location' => l10n.integrationsFieldDefaultlocation,
        'base' => l10n.integrationsFieldBase,
        'update_interval' => l10n.integrationsFieldUpdateinterval,
        'default_country' => l10n.integrationsFieldDefaultcountry,
        'zip_code' => l10n.integrationsFieldZipcode,
        // Unknown keys render their raw bodyKey — never a wrong label.
        _ => bodyKey,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final status = widget.status;
    final configured = status?.configured ?? false;
    final dirty = _dirty;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(widget.service.icon, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _title(l10n),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                // Configured badge (reference status chip).
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: configured
                        ? const Color(0xFFDCFCE7)
                        : scheme.surfaceContainerHighest,
                    borderRadius: AppBorderRadius.badge,
                  ),
                  child: Text(
                    configured
                        ? l10n.integrationsConfigured
                        : l10n.integrationsNotconfigured,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: configured
                          ? const Color(0xFF166534)
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Enabled toggle (reference settings switch).
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                l10n.integrationsEnabled,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            const SizedBox(height: 4),
            for (final field in widget.service.fields) ...[
              TextFormField(
                key: ValueKey('integration-${widget.service.id}-${field.bodyKey}'),
                controller: _controllers[field.bodyKey],
                obscureText: field.secret,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _fieldLabel(l10n, field.bodyKey),
                  helperText: field.secret ? l10n.integrationsApikeyHelper : null,
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: _saving || !dirty ? null : _save,
                icon: _saving
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
      ),
    );
  }
}
