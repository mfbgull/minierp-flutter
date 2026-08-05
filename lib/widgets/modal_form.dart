import 'package:flutter/material.dart';

/// Placeholder modal form scaffold (create/edit dialogs).
///
/// Port the web app's `ModalForm` component (PORTING.md §1 widgets list):
/// title bar, scrollable body, Save/Cancel footer with loading state and
/// validation errors.
class ModalForm extends StatelessWidget {
  const ModalForm({
    super.key,
    required this.title,
    required this.child,
    this.onSave,
    this.saveLabel = 'Save',
    this.cancelLabel = 'Cancel',
  });

  final String title;
  final Widget child;
  final VoidCallback? onSave;
  final String saveLabel;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Flexible(child: SingleChildScrollView(child: child)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(cancelLabel),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: onSave, child: Text(saveLabel)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
