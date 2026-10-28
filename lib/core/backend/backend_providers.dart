import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend_supervisor.dart';

/// Owns the bundled backend for the app's lifetime. Overridden in tests with
/// fake starters/probes.
final backendSupervisorProvider =
    StateNotifierProvider<BackendSupervisor, BackendState>(
      (ref) => BackendSupervisor(),
    );
