// Forecast module models — shapes from `server-reference/forecastService.ts`
// wrapped in the standard `{success, data}` envelope by
// `server/src/controllers/forecastsController.ts` (PORTING.md §12).
//
// Note: the demand endpoint *computes* forecasts on every call
// (`generateAllForecasts()`), so the demand screen hits it per filter
// change; trends/accuracy read stored rows.

import '../../data/models/json_helpers.dart' show asBool, asInt, asNum, asString;

/// A single item's demand forecast (also the dashboard's top-growing /
/// top-declining rows).
class ForecastDemand {
  const ForecastDemand({
    required this.itemId,
    required this.itemCode,
    required this.itemName,
    required this.category,
    required this.currentStock,
    required this.nextWeek,
    required this.nextMonth,
    required this.nextQuarter,
    required this.trend,
    required this.trendPercentage,
    required this.confidence,
    required this.recommendation,
    required this.modelType,
    required this.safetyStock,
    required this.reorderPoint,
    this.biasAdjustment,
    this.seasonalMultiplier,
    required this.isOverride,
    this.lastUpdated,
  });

  factory ForecastDemand.fromJson(Map<String, dynamic> json) {
    final predicted = json['predictedDemand'];
    return ForecastDemand(
      itemId: asInt(json['itemId']) ?? 0,
      itemCode: asString(json['itemCode']) ?? '',
      itemName: asString(json['itemName']) ?? '',
      category: asString(json['category']) ?? '',
      currentStock: asNum(json['currentStock'])?.toDouble() ?? 0,
      nextWeek: _asNum(predicted, 'nextWeek'),
      nextMonth: _asNum(predicted, 'nextMonth'),
      nextQuarter: _asNum(predicted, 'nextQuarter'),
      trend: asString(json['trend']) ?? 'stable',
      trendPercentage: asNum(json['trendPercentage'])?.toDouble() ?? 0,
      confidence: asNum(json['confidence'])?.toDouble() ?? 0,
      recommendation: asString(json['recommendation']) ?? 'monitor',
      modelType: asString(json['modelType']) ?? '',
      safetyStock: asNum(json['safetyStock'])?.toDouble() ?? 0,
      reorderPoint: asNum(json['reorderPoint'])?.toDouble() ?? 0,
      biasAdjustment: asNum(json['biasAdjustment'])?.toDouble(),
      seasonalMultiplier: asNum(json['seasonalMultiplier'])?.toDouble(),
      isOverride: asBool(json['isOverride']),
      lastUpdated: asString(json['lastUpdated']),
    );
  }

  final int itemId;
  final String itemCode;
  final String itemName;
  final String category;

  /// Quantity on hand.
  final double currentStock;
  final double nextWeek;
  final double nextMonth;
  final double nextQuarter;

  /// `growing` | `stable` | `declining`.
  final String trend;
  final double trendPercentage;

  /// 0–100 model confidence.
  final double confidence;

  /// `order_now` | `order_soon` | `monitor` | `adequate`.
  final String recommendation;
  final String modelType;
  final double safetyStock;
  final double reorderPoint;
  final double? biasAdjustment;
  final double? seasonalMultiplier;
  final bool isOverride;
  final String? lastUpdated;

  static double _asNum(Object? predicted, String key) =>
      predicted is Map<String, dynamic>
      ? (asNum(predicted[key]) ?? 0).toDouble()
      : 0;
}

/// One dashboard alert (order_now → critical, order_soon → warning).
class ForecastAlert {
  const ForecastAlert({
    required this.itemId,
    required this.itemName,
    required this.currentStock,
    required this.predictedDemand,
    required this.safetyStock,
    required this.alertLevel,
    required this.recommendation,
  });

  factory ForecastAlert.fromJson(Map<String, dynamic> json) => ForecastAlert(
    itemId: asInt(json['itemId']) ?? 0,
    itemName: asString(json['itemName']) ?? '',
    currentStock: asNum(json['currentStock'])?.toDouble() ?? 0,
    predictedDemand: asNum(json['predictedDemand'])?.toDouble() ?? 0,
    safetyStock: asNum(json['safetyStock'])?.toDouble() ?? 0,
    alertLevel: asString(json['alertLevel']) ?? 'adequate',
    recommendation: asString(json['recommendation']) ?? 'monitor',
  );

  final int itemId;
  final String itemName;
  final double currentStock;
  final double predictedDemand;
  final double safetyStock;

  /// `critical` | `warning` | `monitor` | `adequate`.
  final String alertLevel;
  final String recommendation;
}

/// `GET /forecasts/dashboard` body.
class ForecastDashboardData {
  const ForecastDashboardData({
    required this.totalItems,
    required this.itemsNeedingRestock,
    required this.avgConfidence,
    required this.criticalAlerts,
    this.avgAccuracy,
    required this.alerts,
    required this.topGrowing,
    required this.topDeclining,
  });

  factory ForecastDashboardData.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    List<dynamic> asList(String key) =>
        json[key] is List ? json[key] as List : const [];
    return ForecastDashboardData(
      totalItems: _asIntIn(summary, 'totalItems'),
      itemsNeedingRestock: _asIntIn(summary, 'itemsNeedingRestock'),
      avgConfidence: _asIntIn(summary, 'avgConfidence'),
      criticalAlerts: _asIntIn(summary, 'criticalAlerts'),
      avgAccuracy: _asNumIn(summary, 'avgAccuracy'),
      alerts: [
        for (final a in asList('alerts'))
          ForecastAlert.fromJson(a as Map<String, dynamic>),
      ],
      topGrowing: [
        for (final f in asList('topGrowing'))
          ForecastDemand.fromJson(f as Map<String, dynamic>),
      ],
      topDeclining: [
        for (final f in asList('topDeclining'))
          ForecastDemand.fromJson(f as Map<String, dynamic>),
      ],
    );
  }

  final int totalItems;
  final int itemsNeedingRestock;
  final int avgConfidence;
  final int criticalAlerts;

  /// Avg MAPE over the last 30 days, when accuracy data exists.
  final double? avgAccuracy;
  final List<ForecastAlert> alerts;
  final List<ForecastDemand> topGrowing;
  final List<ForecastDemand> topDeclining;

  static int _asIntIn(Object? summary, String key) =>
      summary is Map<String, dynamic> ? asInt(summary[key]) ?? 0 : 0;

  static double? _asNumIn(Object? summary, String key) =>
      summary is Map<String, dynamic> ? asNum(summary[key])?.toDouble() : null;
}

/// One month of `GET /forecasts/trends` historical data.
class TrendMonth {
  const TrendMonth({required this.month, this.actual, this.predicted, this.movingAvg});

  factory TrendMonth.fromJson(Map<String, dynamic> json) => TrendMonth(
    month: asString(json['month']) ?? '',
    actual: asNum(json['actual'])?.toDouble(),
    predicted: asNum(json['predicted'])?.toDouble(),
    movingAvg: asNum(json['movingAvg'])?.toDouble(),
  );

  final String month;
  final double? actual;
  final double? predicted;
  final double? movingAvg;
}

/// One row of `GET /forecasts/trends` item breakdown.
class BreakdownItem {
  const BreakdownItem({
    required this.itemName,
    required this.totalSold,
    required this.trend,
  });

  factory BreakdownItem.fromJson(Map<String, dynamic> json) => BreakdownItem(
    itemName: asString(json['itemName']) ?? '',
    totalSold: asNum(json['totalSold'])?.toDouble() ?? 0,
    trend: asString(json['trend']) ?? 'stable',
  );

  final String itemName;
  final double totalSold;
  final String trend;
}

class ForecastTrendData {
  const ForecastTrendData({required this.historicalTrends, required this.itemBreakdown});

  factory ForecastTrendData.fromJson(Map<String, dynamic> json) =>
      ForecastTrendData(
        historicalTrends: [
          for (final t in json['historicalTrends'] as List? ?? const [])
            TrendMonth.fromJson(t as Map<String, dynamic>),
        ],
        itemBreakdown: [
          for (final b in json['itemBreakdown'] as List? ?? const [])
            BreakdownItem.fromJson(b as Map<String, dynamic>),
        ],
      );

  final List<TrendMonth> historicalTrends;
  final List<BreakdownItem> itemBreakdown;
}

/// One row of `GET /forecasts/accuracy` (aggregated per item).
class ItemAccuracy {
  const ItemAccuracy({
    required this.itemId,
    required this.itemName,
    required this.itemCode,
    this.mape,
    this.mae,
    this.smape,
    required this.sampleSize,
    this.modelType,
    this.trend,
  });

  factory ItemAccuracy.fromJson(Map<String, dynamic> json) => ItemAccuracy(
    itemId: asInt(json['itemId']) ?? 0,
    itemName: asString(json['itemName']) ?? '',
    itemCode: asString(json['itemCode']) ?? '',
    mape: asNum(json['mape'])?.toDouble(),
    mae: asNum(json['mae'])?.toDouble(),
    smape: asNum(json['smape'])?.toDouble(),
    sampleSize: asInt(json['sampleSize']) ?? 0,
    modelType: asString(json['modelType']),
    trend: asString(json['trend']),
  );

  final int itemId;
  final String itemName;
  final String itemCode;
  final double? mape;
  final double? mae;
  final double? smape;
  final int sampleSize;
  final String? modelType;

  /// `growing` | `stable` | `declining` | null (no forecast yet).
  final String? trend;
}

/// One point of `GET /forecasts/accuracy/:itemId` (a past prediction).
class AccuracyDataPoint {
  const AccuracyDataPoint({
    required this.forecastDate,
    required this.period,
    required this.predicted,
    this.actual,
    this.mape,
    this.mae,
  });

  factory AccuracyDataPoint.fromJson(Map<String, dynamic> json) =>
      AccuracyDataPoint(
        forecastDate: asString(json['forecastDate']) ?? '',
        period: asString(json['period']) ?? '',
        predicted: asNum(json['predicted'])?.toDouble() ?? 0,
        actual: asNum(json['actual'])?.toDouble(),
        mape: asNum(json['mape'])?.toDouble(),
        mae: asNum(json['mae'])?.toDouble(),
      );

  final String forecastDate;
  final String period;
  final double predicted;
  final double? actual;
  final double? mape;
  final double? mae;
}

/// `POST /forecasts/compute-accuracy` data payload `{computed, errors}`.
class ComputeAccuracyResult {
  const ComputeAccuracyResult({required this.computed, required this.errors});

  factory ComputeAccuracyResult.fromJson(Map<String, dynamic> json) =>
      ComputeAccuracyResult(
        computed: asInt(json['computed']) ?? 0,
        errors: asInt(json['errors']) ?? 0,
      );

  final int computed;
  final int errors;
}
