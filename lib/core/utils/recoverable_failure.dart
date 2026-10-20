import 'package:flutter/foundation.dart';

void reportRecoverableFailure(String operation, Object error) {
  debugPrint('MiniERP recovery: $operation (${error.runtimeType})');
}
