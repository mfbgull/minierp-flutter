import 'package:flutter/material.dart';

/// Shared labelled form field (label + error + validation wiring).
/// Port of the web app's form input conventions (dense data screens).
class FormFieldShell extends StatelessWidget {
  const FormFieldShell({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
  });

  final String label;
  final Widget child;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text.rich(
            TextSpan(
              text: label,
              children: [
                if (required)
                  TextSpan(
                    text: ' *',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
              ],
            ),
            style: theme.textTheme.labelLarge,
          ),
        ),
        child,
      ],
    );
  }
}
