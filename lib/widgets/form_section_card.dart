// Shared sectioned card for the data-entry dialogs (purchase / purchase
// order forms): a bordered surface card with an icon chip + title header
// and the form fields below. Keeps the two forms' section styling
// identical without duplicating the chrome (AGENTS.md
// duplicated_logic == false).

import 'package:flutter/material.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

class FormSectionCard extends StatelessWidget {
  const FormSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppBorderRadius.mdRadius,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: AppBorderRadius.smRadius,
                ),
                child: Icon(icon, size: 16, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
