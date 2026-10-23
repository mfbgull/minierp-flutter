import 'package:flutter/material.dart';

/// Shimmer base/highlight colors for the current theme.
///
/// Light mode sweeps toward white; dark mode blends a little of the
/// on-surface ink into the elevated surface so the band stays visible when
/// the two surface-container tones are close.
@visibleForTesting
({Color base, Color highlight}) skeletonShimmerColors(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final base = scheme.surfaceContainerHigh;
  final highlight = Theme.of(context).brightness == Brightness.dark
      ? Color.alphaBlend(scheme.onSurface.withValues(alpha: 0.08), base)
      : scheme.surface;
  return (base: base, highlight: highlight);
}

/// Shares one shimmer controller across every skeleton placeholder in its
/// subtree. A nested [SkeletonShimmer] reuses the outer animation instead of
/// starting another ticker. Reduced-motion users get static placeholders.
class SkeletonShimmer extends StatefulWidget {
  const SkeletonShimmer({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  bool _hasParentScope = false;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _hasParentScope = _SkeletonShimmerScope.maybeOf(context) != null;
    if (_hasParentScope) {
      _controller?.stop();
      return;
    }

    _controller ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (_reduceMotion) {
      _controller!.stop();
    } else if (!_controller!.isAnimating) {
      _controller!.repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasParentScope) return widget.child;
    final controller = _controller;
    if (controller == null) return widget.child;
    return _SkeletonShimmerScope(animation: controller, child: widget.child);
  }
}

class _SkeletonShimmerScope extends InheritedNotifier<Animation<double>> {
  const _SkeletonShimmerScope({
    required Animation<double> animation,
    required super.child,
  }) : super(notifier: animation);

  static Animation<double>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_SkeletonShimmerScope>()
      ?.notifier;
}

/// A single skeleton placeholder bar with a shimmer animation.
///
/// Used as the building block for skeleton screens that replace
/// [CircularProgressIndicator] during loading states.
class SkeletonBar extends StatelessWidget {
  const SkeletonBar({
    super.key,
    this.width = double.infinity,
    this.height = 14,
    this.borderRadius,
  });

  /// Width of the bar. Defaults to [double.infinity] (fills parent).
  final double width;

  /// Height of the bar in logical pixels. Defaults to 14.
  final double height;

  /// Corner radius; defaults to 4.
  final BorderRadiusGeometry? borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = borderRadius ?? const BorderRadius.all(Radius.circular(4));
    return _ShimmerWidget(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: radius,
        ),
      ),
    );
  }
}

/// A rectangular skeleton placeholder (for chart panels, cards, etc.).
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width = double.infinity,
    this.height = double.infinity,
    this.borderRadius,
  });

  final double width;
  final double height;
  final BorderRadiusGeometry? borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = borderRadius ?? const BorderRadius.all(Radius.circular(8));
    return _ShimmerWidget(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: radius,
        ),
      ),
    );
  }
}

/// A circular skeleton placeholder (for avatar / icon placeholders).
class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _ShimmerWidget(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shimmer animation plumbing
// ---------------------------------------------------------------------------

class _ShimmerWidget extends StatelessWidget {
  const _ShimmerWidget({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final animation = _SkeletonShimmerScope.maybeOf(context);
    if (animation == null) return _StandaloneShimmer(child: child);
    return _ShimmerMask(animation: animation, child: child);
  }
}

class _ShimmerMask extends StatelessWidget {
  const _ShimmerMask({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = skeletonShimmerColors(context);

    return AnimatedBuilder(
      animation: animation,
      child: RepaintBoundary(child: child),
      builder: (context, child) {
        // Sweep a bright band from left (-0.5) to right (1.5).
        final dx = -0.5 + animation.value * 2.0;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-dx - 0.5, 0),
              end: Alignment(-dx + 0.5, 0),
              colors: [colors.base, colors.highlight, colors.base],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(bounds);
          },
          child: child,
        );
      },
    );
  }
}

/// Fallback for a bare skeleton outside a [SkeletonShimmer] subtree.
class _StandaloneShimmer extends StatefulWidget {
  const _StandaloneShimmer({required this.child});

  final Widget child;

  @override
  State<_StandaloneShimmer> createState() => _StandaloneShimmerState();
}

class _StandaloneShimmerState extends State<_StandaloneShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion) return widget.child;
    return _ShimmerMask(animation: _controller, child: widget.child);
  }
}

// ---------------------------------------------------------------------------
// Dashboard-specific skeleton compositions
// ---------------------------------------------------------------------------

/// Skeleton matching the KPI strip card layout:
/// icon row + title bar + value bar.
class KpiCardSkeleton extends StatelessWidget {
  const KpiCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const SkeletonCircle(size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: SkeletonBar(height: 12)),
                ],
              ),
              SkeletonBar(height: 18, width: 80),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton matching the full dashboard KPI strip (horizontally scrolling
/// cards). Shows [count] placeholder cards.
class KpiStripSkeleton extends StatelessWidget {
  const KpiStripSkeleton({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: SizedBox(
        height: 110,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: count,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, _) =>
              const SizedBox(width: 180, child: KpiCardSkeleton()),
        ),
      ),
    );
  }
}

/// Skeleton for a chart panel (Sales vs Purchases, etc.):
/// title bar + a large rectangle placeholder + legend bars.
class ChartPanelSkeleton extends StatelessWidget {
  const ChartPanelSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBar(height: 16, width: 160),
              const SizedBox(height: 12),
              const Expanded(
                child: SkeletonBox(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SkeletonBar(height: 10, width: 60),
                  const SizedBox(width: 16),
                  SkeletonBar(height: 10, width: 80),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton for a list panel (Top Customers, Low Stock, etc.):
/// title bar + 5 rows of [bar + text].
class ListPanelSkeleton extends StatelessWidget {
  const ListPanelSkeleton({super.key, this.rows = 5});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBar(height: 16, width: 140),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: rows,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, _) => const _SkeletonListRow(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonListRow extends StatelessWidget {
  const _SkeletonListRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SkeletonCircle(size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBar(height: 12),
              const SizedBox(height: 6),
              SkeletonBar(height: 10, width: 120),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SkeletonBar(height: 12, width: 60),
      ],
    );
  }
}

/// Skeleton for the cash position strip: 4 horizontal cards.
class CashPositionStripSkeleton extends StatelessWidget {
  const CashPositionStripSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SkeletonBar(height: 14, width: 160),
                  const Spacer(),
                  SkeletonBar(height: 12, width: 80),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 68,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 4,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, _) => Container(
                    width: 190,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: const BorderRadius.all(Radius.circular(12)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SkeletonBar(height: 10, width: 80),
                        SizedBox(height: 6),
                        SkeletonBar(height: 16, width: 100),
                        SizedBox(height: 4),
                        SkeletonBar(height: 8, width: 60),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
