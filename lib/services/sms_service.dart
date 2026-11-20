import 'dart:convert';
import 'package:another_telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sms_entry.dart';

class SmsService {
  static const _kQueueKey = 'pending_sms_logs';
  static const _kLastSyncKey = 'sms_log_last_sync_epoch';
  static const _maxQueue = 2000;

  static final Telephony _telephony = Telephony.instance;

  static Future<List<SmsEntry>> fetchInbox({int limit = 200}) async {
    final messages = await _telephony.getInboxSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );
    return messages.take(limit).map((m) => SmsEntry(
          address: m.address ?? 'Unknown',
          body: m.body ?? '',
          date: DateTime.fromMillisecondsSinceEpoch(m.date ?? 0),
          kind: SmsKind.inbox,
        )).toList();
  }

  static Future<List<SmsEntry>> fetchSent({int limit = 200}) async {
    final messages = await _telephony.getSentSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );
    return messages.take(limit).map((m) => SmsEntry(
          address: m.address ?? 'Unknown',
          body: m.body ?? '',
          date: DateTime.fromMillisecondsSinceEpoch(m.date ?? 0),
          kind: SmsKind.sent,
        )).toList();
  }

  static Future<int> captureNewToQueue({int max = 200}) async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncMs = prefs.getInt(_kLastSyncKey) ?? 0;
    final fetchFrom = lastSyncMs == 0
        ? DateTime.now().subtract(const Duration(days: 7))
        : DateTime.fromMillisecondsSinceEpoch(lastSyncMs);

    final inbox = await fetchInbox(limit: max);
    final sent = await fetchSent(limit: max);
    final fresh = [...inbox, ...sent]
        .where((s) => s.date.isAfter(fetchFrom))
        .toList();
    if (fresh.isEmpty) return 0;

    final existing = prefs.getStringList(_kQueueKey) ?? <String>[];
    existing.addAll(fresh.map((s) => jsonEncode(s.toJson())));
    if (existing.length > _maxQueue) {
      existing.removeRange(0, existing.length - _maxQueue);
    }
    await prefs.setStringList(_kQueueKey, existing);
    return fresh.length;
  }

  static Future<List<SmsEntry>> peekQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kQueueKey) ?? <String>[];
    return list.map((s) {
      final j = jsonDecode(s) as Map<String, dynamic>;
      return SmsEntry(
        address: j['address'] as String,
        body: j['body'] as String,
        date: DateTime.parse(j['capturedAt'] as String),
        kind: SmsKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => SmsKind.inbox,
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
}