import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A single recently-viewed entity, persisted locally (no backend).
class RecentItem {
  const RecentItem({
    required this.entityType,
    required this.entityId,
    required this.title,
    required this.subtitle,
    required this.path,
    required this.timestamp,
  });

  factory RecentItem.fromJson(Map<String, dynamic> json) => RecentItem(
        entityType: (json['entityType'] as String?) ?? '',
        entityId: json['entityId'],
        title: (json['title'] as String?) ?? '',
        subtitle: (json['subtitle'] as String?) ?? '',
        path: (json['path'] as String?) ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          (json['timestamp'] as num?)?.toInt() ?? 0,
        ),
      );

  final String entityType;
  final dynamic entityId;
  final String title;
  final String subtitle;
  final String path;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'entityType': entityType,
        'entityId': entityId,
        'title': title,
        'subtitle': subtitle,
        'path': path,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };

  String get key => '$entityType:$entityId';
}

/// SharedPreferences-backed store of the last few opened search results.
class RecentItems {
  RecentItems(this._prefs);

  final SharedPreferences _prefs;

  static const _storageKey = 'global_search_recent';
  static const maxItems = 5;

  static Future<RecentItems> load() async =>
      RecentItems(await SharedPreferences.getInstance());

  List<RecentItem> getItems() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null) return const [];
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final items = [for (final m in list) RecentItem.fromJson(m)];
      items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return items;
    } catch (_) {
      return const [];
    }
  }

  Future<void> addItem(RecentItem item) async {
    final items = getItems().where((i) => i.key != item.key).toList()
      ..insert(0, item);
    final trimmed = items.take(maxItems).toList();
    await _prefs.setString(
      _storageKey,
      jsonEncode([for (final i in trimmed) i.toJson()]),
    );
  }

  Future<void> clear() async => _prefs.remove(_storageKey);
}

final recentItemsProvider = FutureProvider<RecentItems>(
  (_) => RecentItems.load(),
);
