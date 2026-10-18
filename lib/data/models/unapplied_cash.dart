import 'dart:convert';

const maxCashMinor = 9007199254740991;
const cashMethods = ['Cash', 'Bank', 'Easypaisa', 'JazzCash', 'Upaisa'];

Map<String, dynamic> cashObject(Object? value) => switch (value) {
  Map<String, dynamic> object => object,
  _ => throw const FormatException('Invalid cash response'),
};

int cashId(Object? value) {
  if (value is! int || value <= 0 || value > maxCashMinor) {
    throw const FormatException('Invalid cash identifier');
  }
  return value;
}

int cashMinor(Object? value) {
  if (value is! num ||
      !value.isFinite ||
      value < 0 ||
      value * 100 > maxCashMinor) {
    throw const FormatException('Invalid cash amount');
  }
  return (value * 100).round();
}

int parseCashMinor(String text) {
  final value = text.trim();
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) {
    throw const FormatException('Invalid cash amount');
  }
  final parts = value.split('.');
  final whole = int.tryParse(parts.first);
  final fraction = parts.length == 1
      ? 0
      : int.parse(parts.last.padRight(2, '0'));
  if (whole == null || whole > maxCashMinor ~/ 100) {
    throw const FormatException('Invalid cash amount');
  }
  final minor = whole * 100 + fraction;
  if (minor <= 0 || minor > maxCashMinor) {
    throw const FormatException('Invalid cash amount');
  }
  return minor;
}

String cashDate(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Invalid cash date');
  }
  final date = DateTime.tryParse(value);
  if (date == null ||
      date.year > DateTime.now().year + 1 ||
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}' !=
          value) {
    throw const FormatException('Invalid cash date');
  }
  return value;
}

enum CashOperation { receive, apply, refund, reverse }

class CashCapabilities {
  CashCapabilities(Object? json)
    : _policies = Map.unmodifiable(cashObject(json));

  final Map<String, dynamic> _policies;

  String? policy(CashOperation operation) =>
      switch (_policies[operation.name]) {
        String policy => policy,
        _ => null,
      };

  static String expected(CashOperation operation) => switch (operation) {
    CashOperation.receive => 'durable-v1',
    CashOperation.apply || CashOperation.refund => 'permanent-application-v1',
    CashOperation.reverse => 'guarded-status-v1',
  };

  bool supports(CashOperation operation) =>
      policy(operation) == expected(operation);
}

class CashAllocation {
  CashAllocation({required this.invoiceId, required this.amountMinor}) {
    cashId(invoiceId);
    _positiveMinor(amountMinor);
  }

  final int invoiceId;
  final int amountMinor;
}

void _positiveMinor(int amount) {
  if (amount <= 0 || amount > maxCashMinor) {
    throw const FormatException('Invalid cash amount');
  }
}

String _method(String method) {
  if (!cashMethods.contains(method)) {
    throw const FormatException('Invalid cash method');
  }
  return method;
}

class CashRequest {
  CashRequest._(
    this.operation,
    this.customerId,
    this.paymentId,
    Map<String, dynamic> body,
  ) : body = Map.unmodifiable(body) {
    cashId(customerId);
  }

  factory CashRequest.receive({
    required int customerId,
    required int amountMinor,
    required String date,
    String method = 'Cash',
  }) {
    _positiveMinor(amountMinor);
    return CashRequest._(CashOperation.receive, customerId, null, {
      'amount': amountMinor / 100,
      'operation_date': cashDate(date),
      'payment_method': _method(method),
    });
  }

  factory CashRequest.refund({
    required int customerId,
    required int amountMinor,
    required String date,
    String method = 'Cash',
  }) {
    final receive = CashRequest.receive(
      customerId: customerId,
      amountMinor: amountMinor,
      date: date,
      method: method,
    );
    return CashRequest._(CashOperation.refund, customerId, null, {
      'customer_id': customerId,
      ...receive.body,
    });
  }

  factory CashRequest.apply({
    required int customerId,
    required String date,
    required List<CashAllocation> allocations,
  }) {
    if (allocations.isEmpty ||
        allocations.length > 1000 ||
        allocations.map((line) => line.invoiceId).toSet().length !=
            allocations.length) {
      throw const FormatException('Invalid cash allocations');
    }
    final sorted = [...allocations]
      ..sort((left, right) => left.invoiceId.compareTo(right.invoiceId));
    final total = sorted.fold<int>(
      0,
      (total, line) => total + line.amountMinor,
    );
    _positiveMinor(total);
    return CashRequest._(CashOperation.apply, customerId, null, {
      'customer_id': customerId,
      'operation_date': cashDate(date),
      'allocations': List.unmodifiable(
        sorted.map(
          (line) => Map<String, dynamic>.unmodifiable({
            'invoice_id': line.invoiceId,
            'amount': line.amountMinor / 100,
          }),
        ),
      ),
    });
  }

  factory CashRequest.reverse({
    required int customerId,
    required int paymentId,
    required String reason,
  }) {
    cashId(paymentId);
    final trimmed = reason.trim();
    if (trimmed.isEmpty || trimmed.length > 500) {
      throw const FormatException('Invalid reversal reason');
    }
    return CashRequest._(CashOperation.reverse, customerId, paymentId, {
      'reason': trimmed,
    });
  }

  factory CashRequest.fromJson(Object? value) {
    final json = cashObject(value);
    final operation = CashOperation.values.byName(json['operation'] as String);
    final customerId = cashId(json['customer_id']);
    final body = cashObject(json['body']);
    final request = switch (operation) {
      CashOperation.receive => CashRequest.receive(
        customerId: customerId,
        amountMinor: cashMinor(body['amount']),
        date: body['operation_date'] as String,
        method: body['payment_method'] as String,
      ),
      CashOperation.refund => CashRequest.refund(
        customerId: customerId,
        amountMinor: cashMinor(body['amount']),
        date: body['operation_date'] as String,
        method: body['payment_method'] as String,
      ),
      CashOperation.apply => CashRequest.apply(
        customerId: customerId,
        date: body['operation_date'] as String,
        allocations: (body['allocations'] as List).map((value) {
          final row = cashObject(value);
          return CashAllocation(
            invoiceId: cashId(row['invoice_id']),
            amountMinor: cashMinor(row['amount']),
          );
        }).toList(),
      ),
      CashOperation.reverse => CashRequest.reverse(
        customerId: customerId,
        paymentId: cashId(json['payment_id']),
        reason: body['reason'] as String,
      ),
    };
    if (request.fingerprint != jsonEncode(json)) {
      throw const FormatException('Pending cash payload changed');
    }
    return request;
  }

  final CashOperation operation;
  final int customerId;
  final int? paymentId;
  final Map<String, dynamic> body;

  String get path => switch (operation) {
    CashOperation.receive => '/customers/$customerId/unapplied-cash',
    CashOperation.apply => '/unapplied-cash/apply',
    CashOperation.refund => '/unapplied-cash/refund',
    CashOperation.reverse => '/payments/$paymentId/reverse',
  };

  Map<String, dynamic> toJson() => {
    'operation': operation.name,
    'customer_id': customerId,
    'payment_id': paymentId,
    'body': body,
  };
  String get fingerprint => jsonEncode(toJson());
}

class CashResult {
  CashResult(Object? value) {
    final json = cashObject(value);
    paymentId = json['paymentId'] == null ? null : cashId(json['paymentId']);
    applicationId = json['applicationId'] == null
        ? null
        : cashId(json['applicationId']);
    amountMinor = json['amount'] == null ? null : cashMinor(json['amount']);
    voided = json['voided'] == true;
    if (paymentId == null && applicationId == null) {
      throw const FormatException('Missing cash operation result');
    }
  }

  late final int? paymentId;
  late final int? applicationId;
  late final int? amountMinor;
  late final bool voided;
}

class CashReceipt {
  CashReceipt(Object? value) {
    final json = cashObject(value);
    sourceId = cashId(json['source_id']);
    paymentId = cashId(json['payment_id']);
    paymentNo = json['payment_no'] as String;
    date = json['payment_date'] as String;
    method = json['payment_method'] as String;
    originalMinor = cashMinor(json['original_amount']);
    appliedMinor = cashMinor(json['applied_amount']);
    refundedMinor = cashMinor(json['refunded_amount']);
    remainingMinor = cashMinor(json['remaining_amount']);
    voidedAt = json['voided_at'] as String?;
    canReverse = json['can_reverse'] == true && voidedAt == null;
  }

  late final int sourceId;
  late final int paymentId;
  late final String paymentNo;
  late final String date;
  late final String method;
  late final int originalMinor;
  late final int appliedMinor;
  late final int refundedMinor;
  late final int remainingMinor;
  late final String? voidedAt;
  late final bool canReverse;
}

class CashPage<T> {
  CashPage(Object? value, T Function(Object?) parse) {
    final json = cashObject(value);
    final meta = cashObject(json['pagination']);
    final rows = json['data'] as List;
    items = List.unmodifiable(rows.map(parse));
    page = cashId(meta['currentPage']);
    totalPages = meta['totalPages'] as int;
    totalItems = meta['totalItems'] as int;
  }

  late final List<T> items;
  late final int page;
  late final int totalPages;
  late final int totalItems;
}

class CashSummary {
  CashSummary(Object? value) {
    final envelope = cashObject(value);
    final data = cashObject(envelope['data']);
    customerId = cashId(data['customer_id']);
    operationDate = data['operation_date'] as String;
    remainingMinor = cashMinor(data['remaining_amount']);
    availableMinor = cashMinor(data['available_amount']);
    refundableMinor = cashMinor(data['refundable_amount']);
    receipts = CashPage({
      'data': data['receipts'],
      'pagination': envelope['pagination'],
    }, CashReceipt.new);
  }

  late final int customerId;
  late final String operationDate;
  late final int remainingMinor;
  late final int availableMinor;
  late final int refundableMinor;
  late final CashPage<CashReceipt> receipts;
}

class CashActivityLine {
  CashActivityLine(Object? value) {
    final json = cashObject(value);
    sourceId = cashId(json['source_id']);
    invoiceId = json['invoice_id'] == null ? null : cashId(json['invoice_id']);
    invoiceNo = json['invoice_no'] as String?;
    paymentId = json['payment_id'] == null ? null : cashId(json['payment_id']);
    amountMinor = cashMinor(json['amount']);
    kind = json['kind'] as String;
    voidedAt = json['voided_at'] as String?;
  }

  late final int sourceId;
  late final int? invoiceId;
  late final String? invoiceNo;
  late final int? paymentId;
  late final int amountMinor;
  late final String kind;
  late final String? voidedAt;
}

class CashActivity {
  CashActivity(Object? value) {
    final json = cashObject(value);
    applicationId = cashId(json['application_id']);
    operation = CashOperation.values.byName(
      json['operation'].toString().toLowerCase(),
    );
    date = json['operation_date'] as String;
    amountMinor = cashMinor(json['total_amount']);
    paymentId = json['payment_id'] == null ? null : cashId(json['payment_id']);
    lines = List.unmodifiable(
      (json['lines'] as List).map(CashActivityLine.new),
    );
  }

  late final int applicationId;
  late final CashOperation operation;
  late final String date;
  late final int amountMinor;
  late final int? paymentId;
  late final List<CashActivityLine> lines;
}
