// P1 UI audit — one shimmer controller per skeleton tree, and no
// shimmer at all when the OS asks for reduced motion.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/core/theme/app_theme.dart';
import 'package:minierp_app/widgets/skeleton_loader.dart';

void main() {
  testWidgets('shimmer base and highlight stay distinct in both themes', (
    tester,
  ) async {
    late ({Color base, Color highlight}) light;
    late ({Color base, Color highlight}) dark;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            light = skeletonShimmerColors(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) {
            dark = skeletonShimmerColors(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(light.base, isNot(light.highlight));
    expect(dark.base, isNot(dark.highlight));
  });

  testWidgets('a skeleton tree runs exactly one shimmer controller', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SkeletonShimmer(
            child: Column(
              children: [
                for (var i = 0; i < 10; i++) const SkeletonBar(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.binding.transientCallbackCount, 1);
  });

  testWidgets('skeletons render statically when animations are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            body: SkeletonShimmer(
              child: Column(
                children: [
                  for (var i = 0; i < 4; i++) const SkeletonBar(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ShaderMask), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
