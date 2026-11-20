import 'dart:convert';
import 'package:call_log/call_log.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/call_entry.dart';

class CallLogService {
  static const _kQueueKey = 'pending_call_logs';
  static const _kLastSyncKey = 'call_log_last_sync_epoch';
  static const _maxQueue = 2000;

  /// Read from device call log and return the newest [limit] entries.
  static Future<List<CallEntry>> fetch({int limit = 200}) async {
    final entries = await CallLog.query(
  dateFrom: DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch,
);
    return entries.map(_map).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// Read fresh calls since last successful sync and enqueue them.
  static Future<int> captureNewToQueue({int max = 200}) async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncMs = prefs.getInt(_kLastSyncKey) ?? 0;
    final lastSync = DateTime.fromMillisecondsSinceEpoch(lastSyncMs);
    final fetchFrom = lastSyncMs == 0
        ? DateTime.now().subtract(const Duration(days: 7))
        : lastSync;

    final all = await fetch(limit: max);
    final fresh = all.where((e) => e.timestamp.isAfter(fetchFrom)).toList();
    if (fresh.isEmpty) return 0;

    final existing = prefs.getStringList(_kQueueKey) ?? <String>[];
    existing.addAll(fresh.map((e) => jsonEncode(e.toJson())));
    if (existing.length > _maxQueue) {
      existing.removeRange(0, existing.length - _maxQueue);
    }
    await prefs.setStringList(_kQueueKey, existing);
    return fresh.length;
  }

  static Future<List<CallEntry>> peekQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kQueueKey) ?? <String>[];
    return list.map((s) {
      final j = jsonDecode(s) as Map<String, dynamic>;
      return CallEntry(
        number: j['number'] as String,
        cachedName: j['cachedName'] as String?,
        timestamp: DateTime.parse(j['capturedAt'] as String),
        duration: Duration(seconds: (j['durationSeconds'] as num).toInt()),
        kind: CallKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => CallKind.unknown,
        ),
      );
    }).toList();
  }

  static Future<int> queueLength() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_kQueueKey) ?? const []).length;
  }

  static Future<void> dropFirst(int count) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kQueueKey) ?? <String>[];
    if (count >= list.length) {
      await prefs.remove(_kQueueKey);
    } else {
      list.removeRange(0, count);
      await prefs.setStringList(_kQueueKey, list);
    }
  }

  static Future<void> markSynced(DateTime t) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastSyncKey, t.millisecondsSinceEpoch);
  }

  static CallEntry _map(CallLogEntry e) => CallEntry(
        number: e.number ?? 'Unknown',
        cachedName: e.name,
        timestamp: DateTime.fromMillisecondsSinceEpoch(e.timestamp ?? 0),
        duration: Duration(seconds: e.duration ?? 0),
        kind: _kindFrom(e.callType),
      );

  static CallKind _kindFrom(CallType? t) {
    switch (t) {
      case CallType.incoming: return CallKind.incoming;
      case CallType.outgoing: return CallKind.outgoing;
      case CallType.missed:   return CallKind.missed;
      case CallType.rejected: return CallKind.rejected;
      default:                return CallKind.unknown;
    }
  }
}