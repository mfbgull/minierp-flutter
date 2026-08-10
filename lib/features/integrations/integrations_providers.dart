// Integrations providers — one future that loads the per-service
// `{enabled, configured}` flags (`GET /integrations/settings`) for the
// IntegrationsScreen's service cards. Editable field state lives in the
// screen (the server never returns key values); refresh invalidates here.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import 'integration_models.dart' show IntegrationServiceStatus;
import 'integrations_repository.dart' show integrationsRepositoryProvider;

/// `service id → status`, in server order.
final integrationsStatusProvider =
    FutureProvider<Map<String, IntegrationServiceStatus>>((ref) async {
      final result = await ref
          .watch(integrationsRepositoryProvider)
          .status();
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });
