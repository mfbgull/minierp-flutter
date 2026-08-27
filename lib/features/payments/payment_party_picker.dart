// Party pickers for the unified Payments screen's "New Payment" menu.
//
// The global Payments screen has no pre-bound supplier/employee (unlike the
// supplier/employee detail screens), so before opening the supplier-payment
// modal or salary-payment dialog it asks the user to pick one. Each picker
// reuses the existing repository `list` call and the app-wide
// [SearchableSelect] — no new data layer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/supplier.dart' show Supplier;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/paged_request.dart' show PagedRequest;
import '../../data/repositories/supplier_repository.dart'
    show supplierRepositoryProvider;
import '../../features/employees/employee_models.dart' show Employee;
import '../../features/employees/employee_repository.dart'
    show EmployeeFilters, employeeRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/searchable_select.dart';

/// All suppliers (large page) for the picker — mirrors
/// `paymentCustomerOptionsProvider` but for suppliers.
final _supplierOptionsProvider = FutureProvider<List<Supplier>>((ref) async {
  final result = await ref
      .watch(supplierRepositoryProvider)
      .list(const PagedRequest(limit: 500));
  return switch (result) {
    ApiSuccess(:final data) => data.items,
    ApiFailure(:final error) => throw error,
  };
});

/// All employees (large page) for the picker.
final _employeeOptionsProvider = FutureProvider<List<Employee>>((ref) async {
  final result = await ref
      .watch(employeeRepositoryProvider)
      .list(const EmployeeFilters(limit: 500));
  return switch (result) {
    ApiSuccess(:final data) => data.items,
    ApiFailure(:final error) => throw error,
  };
});

/// Picks a supplier from the global supplier list. Returns null on cancel.
Future<Supplier?> showSupplierPickerDialog(BuildContext context) =>
    showDialog<Supplier?>(
      context: context,
      builder: (dialogContext) => _PartyPickerDialog<Supplier>(
        title: AppLocalizations.of(dialogContext)!.paymentsSelectSupplier,
        optionsProvider: _supplierOptionsProvider,
        labelBuilder: (s) => s.supplierName,
      ),
    );

/// Picks an employee from the global employee list. Returns null on cancel.
Future<Employee?> showEmployeePickerDialog(BuildContext context) =>
    showDialog<Employee?>(
      context: context,
      builder: (dialogContext) => _PartyPickerDialog<Employee>(
        title: AppLocalizations.of(dialogContext)!.paymentsSelectEmployee,
        optionsProvider: _employeeOptionsProvider,
        labelBuilder: (e) => e.fullName,
      ),
    );

class _PartyPickerDialog<T> extends ConsumerStatefulWidget {
  const _PartyPickerDialog({
    required this.title,
    required this.optionsProvider,
    required this.labelBuilder,
  });

  final String title;
  final ProviderListenable<AsyncValue<List<T>>> optionsProvider;
  final String Function(T) labelBuilder;

  @override
  ConsumerState<_PartyPickerDialog<T>> createState() =>
      _PartyPickerDialogState<T>();
}

class _PartyPickerDialogState<T> extends ConsumerState<_PartyPickerDialog<T>> {
  T? _selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final options = ref.watch(widget.optionsProvider);

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: options.when(
          data: (items) => SearchableSelect<T>(
            items: items,
            selected: _selected,
            labelBuilder: widget.labelBuilder,
            hint: widget.title,
            searchHint: widget.title,
            onChanged: (value) => setState(() => _selected = value),
          ),
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Text(error.toString()),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.of(context).pop(_selected),
          child: Text(l10n.commonConfirm),
        ),
      ],
    );
  }
}
