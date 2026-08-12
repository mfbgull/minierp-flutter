// Shared form helpers for the create/edit dialogs (PORTING.md §1 ModalForm
// pattern) — the item/customer/expense forms otherwise duplicate these
// verbatim (AGENTS.md self-audit: duplicated_logic == false). Validator
// messages are feature-specific l10n keys, passed in by the caller.

import 'package:flutter/material.dart';

/// `14.0` → "14", `12.5` → "12.5" — trims the trailing `.0` that
/// `double.toString()` would add to whole numbers in form prefills.
String numText(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

/// Non-empty string validator; [message] is shown when blank.
String? requiredValidator(String? value, String message) =>
    (value == null || value.trim().isEmpty) ? message : null;

/// Numeric-field validator: must be present, parse as a number, and be
/// >= 0 (the zod schemas coerce numbers with `.min(0)`).
String? nonNegativeNumberValidator(
  String? value, {
  required String emptyMessage,
  required String invalidMessage,
  required String nonNegativeMessage,
}) {
  if (value == null || value.trim().isEmpty) return emptyMessage;
  final parsed = double.tryParse(value.trim());
  if (parsed == null) return invalidMessage;
  if (parsed < 0) return nonNegativeMessage;
  return null;
}

/// [TextFormField.onFieldSubmitted] handler that saves the form — pass
/// it on every **single-line** text field so pressing Enter (the
/// keyboard's action key) submits without reaching for the Save button.
/// The submit method validates first, so a premature Enter just surfaces
/// the field errors; fields are disabled while a save is in flight, so
/// double-submits can't happen. Multi-line fields
/// (description/address/notes) intentionally keep Enter = newline and are
/// left without this handler.
ValueChanged<String> submitOnEnter(VoidCallback onSubmit) => (_) => onSubmit();

/// The dense input decoration used by every field in the form dialogs.
InputDecoration formInputDecoration({String? hintText}) => InputDecoration(
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  hintText: hintText,
);

/// Inline API-error banner shown above the dialog footer on ApiFailure.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
