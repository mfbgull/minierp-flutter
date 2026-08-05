import 'package:flutter/material.dart';

/// Placeholder for the searchable dropdown/autocomplete used across
/// editable grids and forms.
///
/// PORTING.md §6: port the `GenericSearchableCell` pattern from
/// `references/components/shared/` — type-ahead against
/// `GET /inventory/items?search=` etc., keyboard navigation, debounced
/// search.
class SearchableSelect<T> extends StatelessWidget {
  const SearchableSelect({
    super.key,
    required this.items,
    this.selected,
    this.onChanged,
    this.labelBuilder,
    this.validator,
    this.enabled = true,
  });

  final List<T> items;
  final T? selected;
  final ValueChanged<T?>? onChanged;
  final String Function(T)? labelBuilder;

  /// Form validation for the underlying dropdown (e.g. a required field).
  final FormFieldValidator<T>? validator;

  /// Disabled while a form is submitting (matches the text fields).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // TODO(porting): Autocomplete<T> wired to a debounced repository
    // search with keyboard nav. See PORTING.md §6 + GenericSearchableCell.
    return DropdownButtonFormField<T>(
      initialValue: selected,
      // Ellipsize long selected values instead of overflowing the
      // dropdown's Row (same overflow the toolbar filters had).
      isExpanded: true,
      items: [
        for (final item in items)
          DropdownMenuItem(
            value: item,
            child: Text(labelBuilder?.call(item) ?? item.toString()),
          ),
      ],
      onChanged: enabled ? onChanged : null,
      validator: validator,
    );
  }
}
