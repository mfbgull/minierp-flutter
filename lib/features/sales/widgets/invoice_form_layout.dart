import 'package:flutter/material.dart';

/// Wide (desktop) layout: line-items grid left, 275px summary column right.
///
/// The grid column ends with a compact three-field row (notes, tax, discount)
/// so the space under the grid stays small. The right column stacks the totals
/// card above the payment panel; only that pair scrolls, while the error banner
/// and the action buttons stay pinned at the bottom of the column.
class InvoiceFormWideLayout extends StatelessWidget {
  const InvoiceFormWideLayout({
    super.key,
    required this.header,
    required this.heading,
    required this.grid,
    required this.totals,
    required this.footer,
    required this.panel,
    required this.buttons,
    required this.gridMinHeight,
    this.errorBanner,
  });

  final Widget header;
  final Widget heading;
  final Widget grid;
  final Widget totals;
  final Widget footer;
  final Widget panel;
  final Widget buttons;
  final Widget? errorBanner;
  final double gridMinHeight;

  /// Width of the right-hand summary column.
  static const double sidebarWidth = 275;

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
                          constraints: BoxConstraints(minHeight: gridMinHeight),
                          child: grid,
                        ),
                      ),
                      const SizedBox(height: 8),
                      footer,
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: sidebarWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              totals,
                              const SizedBox(height: 8),
                              panel,
                            ],
                          ),
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

/// Stacked scrollable layout for compact windows: grid, the three-field row,
/// then totals, payment, error banner and buttons in one downward flow.
class InvoiceFormNarrowLayout extends StatelessWidget {
  const InvoiceFormNarrowLayout({
    super.key,
    required this.header,
    required this.heading,
    required this.grid,
    required this.totals,
    required this.footer,
    required this.panel,
    required this.buttons,
    required this.gridMinHeight,
    this.errorBanner,
  });

  final Widget header;
  final Widget heading;
  final Widget grid;
  final Widget totals;
  final Widget footer;
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
          footer,
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: InvoiceFormWideLayout.sidebarWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  totals,
                  const SizedBox(height: 8),
                  panel,
                  if (errorBanner != null) ...[
                    const SizedBox(height: 10),
                    errorBanner!,
                  ],
                  const SizedBox(height: 12),
                  buttons,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
