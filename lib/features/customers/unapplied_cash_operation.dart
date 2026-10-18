import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/unapplied_cash.dart';
import '../../data/repositories/api_result.dart';
import '../../data/repositories/unapplied_cash_repository.dart';
import '../../core/utils/idempotency_key.dart';

typedef CashScope = ({String server, int userId});

class PendingCashOperation {
  const PendingCashOperation({
    required this.request,
    required this.key,
    required this.firstDispatchedAt,
    this.replayPolicy,
  });

  final CashRequest request;
  final String key;
  final DateTime firstDispatchedAt;
  final String? replayPolicy;
}

class CashPendingStore {
  String _key(CashScope scope) =>
      'unapplied_cash_pending/${base64Url.encode(utf8.encode(jsonEncode([scope.server, scope.userId])))}';

  Future<PendingCashOperation?> load(CashScope scope) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(scope));
    if (raw == null) return null;
    final json = cashObject(jsonDecode(raw));
    final key = json['key'] as String;
    final timestamp = DateTime.tryParse(json['first_dispatched_at'] as String);
    if (json['version'] != 1 ||
        key.length < 8 ||
        key.length > 200 ||
        key.trim() != key ||
        timestamp == null) {
      throw const FormatException('Invalid pending cash request');
    }
    return PendingCashOperation(
      request: CashRequest.fromJson(json['request']),
      key: key,
      firstDispatchedAt: timestamp,
      replayPolicy: json['replay_policy'] as String?,
    );
  }

  Future<void> save(CashScope scope, PendingCashOperation pending) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      _key(scope),
      jsonEncode({
        'version': 1,
        'request': pending.request.toJson(),
        'key': pending.key,
        'first_dispatched_at': pending.firstDispatchedAt
            .toUtc()
            .toIso8601String(),
        'replay_policy': pending.replayPolicy,
      }),
    );
    if (!saved) throw StateError('Pending cash request could not be saved');
  }

  Future<void> clear(CashScope scope) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(_key(scope))) {
      throw StateError('Pending cash request could not be cleared');
    }
  }
}

enum CashOperationPhase {
  idle,
  ready,
  sending,
  failed,
  recoveryRequired,
  succeeded,
  alreadyVoided,
}

class CashOperationState {
  const CashOperationState({
    this.phase = CashOperationPhase.idle,
    this.pending,
    this.error,
    this.result,
  });
  final CashOperationPhase phase;
  final PendingCashOperation? pending;
  final ApiError? error;
  final CashResult? result;
}

class CashOperationController extends StateNotifier<CashOperationState> {
  CashOperationController({
    required this.repository,
    required this.store,
    required this.scope,
    required this.isCurrentScope,
    required this.onSuccess,
  }) : super(const CashOperationState());

  final UnappliedCashRepository repository;
  final CashPendingStore store;
  final CashScope scope;
  final bool Function() isCurrentScope;
  final void Function(int customerId) onSuccess;
  bool _busy = false;

  void _set(CashOperationState value) {
    if (mounted) state = value;
  }

  void _ensureScope() {
    if (!mounted || !isCurrentScope() || repository.server != scope.server) {
      throw const ApiError(
        message: 'Return to the original session to recover this operation',
        code: 'CASH_SCOPE_CHANGED',
      );
    }
  }

  Future<void> restore() async {
    if (_busy) return;
    _busy = true;
    try {
      _ensureScope();
      final pending = await store.load(scope);
      _ensureScope();
      _set(
        CashOperationState(
          phase: pending == null
              ? CashOperationPhase.idle
              : CashOperationPhase.ready,
          pending: pending,
        ),
      );
    } catch (_) {
      _set(
        const CashOperationState(
          phase: CashOperationPhase.recoveryRequired,
          error: ApiError(
            message: 'Pending operation could not be recovered safely',
            code: 'CASH_RECOVERY_REQUIRED',
          ),
        ),
      );
    } finally {
      _busy = false;
    }
  }

  Future<ApiResult<CashResult>> start(CashRequest request) => _perform(request);
  Future<ApiResult<CashResult>> resume() => _perform(null);

  Future<ApiResult<CashResult>> _perform(CashRequest? request) async {
    if (_busy) {
      return const ApiFailure(
        ApiError(message: 'Operation already in progress', code: 'CASH_BUSY'),
      );
    }
    _busy = true;
    PendingCashOperation? pending;
    _set(
      CashOperationState(
        phase: CashOperationPhase.sending,
        pending: state.pending,
      ),
    );
    try {
      _ensureScope();
      pending = await store.load(scope);
      _ensureScope();
      if (request != null && pending != null) {
        throw const ApiError(
          message: 'Recover the existing operation before starting another',
          code: 'CASH_PENDING_OPERATION',
        );
      }
      if (request == null && pending == null) {
        _set(const CashOperationState());
        return const ApiFailure(
          ApiError(message: 'No pending operation', code: 'CASH_NO_PENDING'),
        );
      }
      final command = pending?.request ?? request!;
      final expected = CashCapabilities.expected(command.operation);
      if (pending != null && pending.replayPolicy != expected) {
        throw const ApiError(
          message:
              'The original replay guarantee is unknown; verify this operation before retrying',
          code: 'CASH_RECOVERY_REQUIRED',
        );
      }
      final capability = await repository.capabilities();
      _ensureScope();
      if (capability case ApiFailure(:final error)) throw error;
      if (!capability.requireData.supports(command.operation)) {
        throw const ApiError(
          message:
              'The server does not support safe recovery for this operation',
          code: 'CASH_REPLAY_UNSUPPORTED',
        );
      }
      if (pending == null) {
        pending = PendingCashOperation(
          request: command,
          key: IdempotencyKeyCache(prefix: 'ucash').keyFor(command.toJson()),
          firstDispatchedAt: DateTime.now().toUtc(),
          replayPolicy: expected,
        );
        await store.save(scope, pending);
        _ensureScope();
      }
      if (request == null && command.operation == CashOperation.reverse) {
        final voided = await _reverseRecovery(command);
        if (voided != null) {
          await _complete(pending, voided, CashOperationPhase.alreadyVoided);
          return ApiSuccess(voided);
        }
      }
      _ensureScope();
      _set(
        CashOperationState(phase: CashOperationPhase.sending, pending: pending),
      );
      final result = await repository.execute(command, pending.key);
      if (result case ApiSuccess(:final data)) {
        await _complete(pending, data, CashOperationPhase.succeeded);
      } else if (result case ApiFailure(:final error)) {
        if (request != null &&
            !error.outcomeUnknown &&
            error.code != 'IDEMPOTENCY_CONFLICT' &&
            [400, 401, 403, 404, 409, 422].contains(error.statusCode)) {
          await store.clear(scope);
          pending = null;
        }
        _set(
          CashOperationState(
            phase: pending == null
                ? CashOperationPhase.failed
                : CashOperationPhase.recoveryRequired,
            pending: pending,
            error: error,
          ),
        );
      }
      return result;
    } catch (failure) {
      final error = failure is ApiError
          ? failure
          : const ApiError(
              message:
                  'Pending operation could not be stored or recovered safely',
              code: 'CASH_RECOVERY_REQUIRED',
            );
      _set(
        CashOperationState(
          phase: pending == null && failure is ApiError
              ? CashOperationPhase.failed
              : CashOperationPhase.recoveryRequired,
          pending: pending,
          error: error,
        ),
      );
      return ApiFailure(error);
    } finally {
      _busy = false;
    }
  }

  Future<CashResult?> _reverseRecovery(CashRequest command) async {
    final result = await repository.payment(command.paymentId!);
    _ensureScope();
    if (result case ApiFailure(:final error)) throw error;
    final payment = result.requireData;
    if (payment.id != command.paymentId ||
        payment.customerId != command.customerId ||
        payment.paymentKind != 'UNAPPLIED_RECEIPT') {
      throw const ApiError(
        message: 'Receipt status could not be verified',
        code: 'CASH_RECOVERY_REQUIRED',
      );
    }
    if (payment.voidedAt != null) {
      return CashResult({'paymentId': payment.id, 'voided': true});
    }
    var page = 1;
    while (true) {
      final result = await repository.summary(
        command.customerId,
        page: page,
        limit: 100,
      );
      _ensureScope();
      if (result case ApiFailure(:final error)) throw error;
      final receipts = result.requireData.receipts;
      for (final receipt in receipts.items) {
        if (receipt.paymentId == command.paymentId) {
          if (receipt.canReverse) return null;
          throw const ApiError(
            message: 'Receipt has dependencies and cannot be reversed',
            code: 'CASH_RECEIPT_NOT_REVERSIBLE',
          );
        }
      }
      if (page >= receipts.totalPages || receipts.items.isEmpty) {
        throw const ApiError(
          message: 'Receipt status could not be verified',
          code: 'CASH_RECOVERY_REQUIRED',
        );
      }
      page++;
    }
  }

  Future<void> _complete(
    PendingCashOperation pending,
    CashResult result,
    CashOperationPhase phase,
  ) async {
    await store.clear(scope);
    _set(CashOperationState(phase: phase, result: result));
    if (mounted && isCurrentScope()) onSuccess(pending.request.customerId);
  }
}
