import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Keeps a movable dialog inside the viewport. The offset is measured from
/// the screen center (the un-translated Dialog position), and the dialog's
/// *rendered* size is used — not its max constraints.
Offset clampDialogOffset({
  required Offset offset,
  required Size dialogSize,
  required Size screenSize,
  double margin = 8,
}) {
  final maxDx = math.max(
    0.0,
    (screenSize.width - dialogSize.width) / 2 - margin,
  );
  final maxDy = math.max(
    0.0,
    (screenSize.height - dialogSize.height) / 2 - margin,
  );
  return Offset(
    offset.dx.clamp(-maxDx, maxDx).toDouble(),
    offset.dy.clamp(-maxDy, maxDy).toDouble(),
  );
}

/// Returns the offset that snaps the rendered dialog to its nearest edge,
/// or null when no edge is within [threshold] pixels.
Offset? snapDialogOffset({
  required Offset offset,
  required Size dialogSize,
  required Size screenSize,
  double margin = 8,
  double threshold = 40,
}) {
  final maxDx = math.max(
    0.0,
    (screenSize.width - dialogSize.width) / 2 - margin,
  );
  final maxDy = math.max(
    0.0,
    (screenSize.height - dialogSize.height) / 2 - margin,
  );

  final left = screenSize.width / 2 + offset.dx - dialogSize.width / 2;
  final right = left + dialogSize.width;
  final top = screenSize.height / 2 + offset.dy - dialogSize.height / 2;
  final bottom = top + dialogSize.height;

  double? targetDx;
  double? targetDy;

  if (left <= threshold) {
    targetDx = -maxDx;
  } else if (screenSize.width - right <= threshold) {
    targetDx = maxDx;
  }
  if (top <= threshold) {
    targetDy = -maxDy;
  } else if (screenSize.height - bottom <= threshold) {
    targetDy = maxDy;
  }

  if (targetDx == null && targetDy == null) return null;

  return clampDialogOffset(
    offset: Offset(targetDx ?? offset.dx, targetDy ?? offset.dy),
    dialogSize: dialogSize,
    screenSize: screenSize,
    margin: margin,
  );
}
