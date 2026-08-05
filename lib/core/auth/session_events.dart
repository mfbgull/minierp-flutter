import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Broadcast channel for session-level events emitted by the HTTP layer.
///
/// The dio interceptor observes 401s (expired/invalid token). It can't
/// reach `authProvider` directly — `dioProvider` is *upstream* of it, so a
/// direct dependency would be circular — so it emits here instead, and the
/// app (which sits above both) reacts by expiring the session.
class SessionEvents {
  final StreamController<void> _unauthorized = StreamController<void>.broadcast();

  /// Fires once per 401 response observed by the shared dio client.
  Stream<void> get unauthorized => _unauthorized.stream;

  void notifyUnauthorized() {
    if (!_unauthorized.isClosed) _unauthorized.add(null);
  }

  void dispose() => _unauthorized.close();
}

final sessionEventsProvider = Provider<SessionEvents>((ref) {
  final events = SessionEvents();
  ref.onDispose(events.dispose);
  return events;
});

/// Stream provider so widgets can `ref.listen` for 401 events.
final unauthorizedEventsProvider = StreamProvider<void>(
  (ref) => ref.watch(sessionEventsProvider).unauthorized,
);
