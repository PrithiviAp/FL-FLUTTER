import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationSnapshot {
  final double lat, lng, accuracy;
  final DateTime ts;
  LocationSnapshot(this.lat, this.lng, this.accuracy, this.ts);

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'accuracyMeters': accuracy,
        'capturedAt': ts.toIso8601String(),
      };

  factory LocationSnapshot.fromJson(Map<String, dynamic> j) => LocationSnapshot(
        (j['lat'] as num).toDouble(),
        (j['lng'] as num).toDouble(),
        (j['accuracyMeters'] as num?)?.toDouble() ?? 0,
        DateTime.parse(j['capturedAt'] as String),
      );
}

class LocationService {
  static const _kQueueKey = 'pending_location_pings';
  static const _maxQueue = 2000;

  static Future<bool> isGpsEnabled() => Geolocator.isLocationServiceEnabled();

  static Future<LocationSnapshot?> captureOnce() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );
      return LocationSnapshot(p.latitude, p.longitude, p.accuracy, DateTime.now());
    } catch (_) {
      return null;
    }
  }

  static Future<void> enqueue(LocationSnapshot snap) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kQueueKey) ?? <String>[];
    list.add(jsonEncode(snap.toJson()));
    if (list.length > _maxQueue) {
      list.removeRange(0, list.length - _maxQueue);
    }
    await prefs.setStringList(_kQueueKey, list);
  }

  static Future<List<LocationSnapshot>> peekQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kQueueKey) ?? <String>[];
    return list
        .map((s) {
          try {
            return LocationSnapshot.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<LocationSnapshot>()
        .toList();
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

  static Future<void> clearQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kQueueKey);
  }
}