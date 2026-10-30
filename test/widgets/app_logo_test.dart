import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:minierp_app/widgets/app_logo.dart';

/// BUG/branding: the sidebar's leading mark was a generic Material glyph
/// (Icons.inventory_2), not the app logo. `AppLogo` bundles
/// `assets/logo.png` (regenerated from the committed logo.png); these tests
/// pin the asset registration against accidental removal from pubspec.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('assets/logo.png is bundled and decodes at 256x256 with alpha', () async {
    final data = await rootBundle.load('assets/logo.png');
    expect(data.lengthInBytes, greaterThan(0));

    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 256);
    expect(frame.image.height, 256);

    // The four corners must be transparent: logo.png has none baked in
    // (alpha=False at 1254x1254); the bundled copy is corner-floodfilled.
    final rgba = (await frame.image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    ))!.buffer.asUint8List();
    bool cornerFullyTransparent(int x, int y) {
      final i = (y * frame.image.width + x) * 4;
      return rgba[i + 3] == 0;
    }

    expect(cornerFullyTransparent(0, 0), isTrue, reason: 'top-left corner');
    expect(cornerFullyTransparent(255, 0), isTrue, reason: 'top-right corner');
    expect(cornerFullyTransparent(0, 255), isTrue, reason: 'bottom-left corner');
    expect(
      cornerFullyTransparent(255, 255),
      isTrue,
      reason: 'bottom-right corner',
    );
    // Progress-guard the decode: the encoded asset must not be a placeholder.
    expect(data.lengthInBytes, greaterThan(20000));
  });

  testWidgets('AppLogo renders the bundled asset at the requested size', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppLogo(size: 40),
            ),
          ),
        ),
      ),
    );
    // Force the image stream to resolve; a missing/broken asset throws here.
    await tester.runAsync(() async {});

    final image = tester.widget<Image>(
      find.byType(Image),
    );
    expect(image.image, isA<AssetImage>());
    expect((image.image as AssetImage).assetName, 'assets/logo.png');
    expect(image.width, 40);
    expect(image.height, 40);
  });
}
