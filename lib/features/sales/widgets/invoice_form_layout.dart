import 'package:flutter/material.dart';

/// Fixed-height two-column layout (spec §3.1): grid left, payment +
/// error + buttons right, totals + notes under the grid.
class InvoiceFormWideLayout extends StatelessWidget {
  const InvoiceFormWideLayout({
    super.key,
    required this.header,
    required this.heading,
    required this.grid,
    required this.totals,
    required this.notes,
    required this.panel,
    required this.buttons,
    required this.gridMinHeight,
    this.errorBanner,
  });

  final Widget header;
  final Widget heading;
  final Widget grid;
  final Widget totals;
  final Widget notes;
  final Widget panel;
  final Widget buttons;
  final Widget? errorBanner;
  final double gridMinHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: header,
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      heading,
                      const SizedBox(height: 8),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: gridMinHeight,
                          ),
                          child: grid,
                        ),
                      ),
                      const SizedBox(height: 8),
                      totals,
                      const SizedBox(height: 8),
                      notes,
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 250,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: panel,
                        ),
                      ),
                      if (errorBanner != null) ...[
                        const SizedBox(height: 8),
                        errorBanner!,
                      ],
                      const SizedBox(height: 10),
                      buttons,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Stacked scrollable layout (spec §3.2) for compact windows.
class InvoiceFormNarrowLayout extends StatelessWidget {
  const InvoiceFormNarrowLayout({
    super.key,
    required this.header,
    required this.heading,
    required this.grid,
    required this.totals,
    required this.notes,
    required this.panel,
    required this.buttons,
    required this.gridMinHeight,
    this.errorBanner,
  });

  final Widget header;
  final Widget heading;
  final Widget grid;
  final Widget totals;
  final Widget notes;
  final Widget panel;
  final Widget buttons;
  final Widget? errorBanner;
  final double gridMinHeight;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 10),
          heading,
          const SizedBox(height: 8),
          SizedBox(height: gridMinHeight, child: grid),
          const SizedBox(height: 8),
          totals,
          const SizedBox(height: 8),
          notes,
          const SizedBox(height: 12),
          panel,
          if (errorBanner != null) ...[const SizedBox(height: 10), errorBanner!],
          const SizedBox(height: 12),
          buttons,
        ],
      ),
    );
  }
}
