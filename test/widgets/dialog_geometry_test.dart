// P1 UI audit — movable-dialog geometry must use rendered bounds and
// keep the dialog reachable.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/widgets/dialog_geometry.dart';

void main() {
  const screen = Size(1000, 800);
  const dialog = Size(400, 300);

  group('clampDialogOffset', () {
    test('keeps a fitting dialog fully inside the viewport', () {
      expect(
        clampDialogOffset(
          offset: const Offset(1000, 1000),
          dialogSize: dialog,
          screenSize: screen,
        ),
        const Offset(292, 242),
      );
      expect(
        clampDialogOffset(
          offset: const Offset(-1000, -1000),
          dialogSize: dialog,
          screenSize: screen,
        ),
        const Offset(-292, -242),
      );
    });

    test('leaves an in-bounds offset untouched', () {
      expect(
        clampDialogOffset(
          offset: const Offset(100, -50),
          dialogSize: dialog,
          screenSize: screen,
        ),
        const Offset(100, -50),
      );
    });

    test('centers a dialog larger than the viewport', () {
      expect(
        clampDialogOffset(
          offset: const Offset(200, 200),
          dialogSize: const Size(1200, 900),
          screenSize: screen,
        ),
        Offset.zero,
      );
    });
  });

  group('snapDialogOffset', () {
    test('snaps to the left edge when the rendered dialog is near it', () {
      expect(
        snapDialogOffset(
          offset: const Offset(-288, 0),
          dialogSize: dialog,
          screenSize: screen,
        ),
        const Offset(-292, 0),
      );
    });

    test('snaps to the right edge when the rendered dialog is near it', () {
      expect(
        snapDialogOffset(
          offset: const Offset(288, 0),
          dialogSize: dialog,
          screenSize: screen,
        ),
        const Offset(292, 0),
      );
    });

    test('snaps to the nearest vertical edge', () {
      expect(
        snapDialogOffset(
          offset: const Offset(0, 240),
          dialogSize: dialog,
          screenSize: screen,
        ),
        const Offset(0, 242),
      );
    });

    test('does nothing in the middle of the viewport', () {
      expect(
        snapDialogOffset(
          offset: Offset.zero,
          dialogSize: dialog,
          screenSize: screen,
        ),
        isNull,
      );
    });
  });
}
