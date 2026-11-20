import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  static const _kBaseUrl = 'baseUrl';
  static const _kDeviceKey = 'deviceKey';

  static String? _baseUrl;
  static String? _deviceKey;

  static String get baseUrl {
    final u = _baseUrl;
    if (u == null) throw StateError('ApiClient not initialised');
    return u;
  }

  static String? get deviceKey => _deviceKey;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_kBaseUrl);
    _deviceKey = prefs.getString(_kDeviceKey);
  }

  static Future<void> saveConfig({
    required String baseUrl,
    required String deviceKey,
  }) async {
    _baseUrl = baseUrl;
    _deviceKey = deviceKey;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, baseUrl);
    await prefs.setString(_kDeviceKey, deviceKey);
  }

  static Future<void> clear() async {
    _baseUrl = null;
    _deviceKey = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kBaseUrl);
    await prefs.remove(_kDeviceKey);
  }

  static Future<bool> isPaired() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_kBaseUrl);
    final key = prefs.getString(_kDeviceKey);
    _baseUrl = url;
    _deviceKey = key;
    return url != null && key != null;
  }

  static Dio deviceDio({Duration? receiveTimeout}) {
    if (_baseUrl == null || _deviceKey == null) {
      throw StateError('Device not paired');
    }
    return Dio(BaseOptions(
      baseUrl: _baseUrl!,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: receiveTimeout ?? const Duration(seconds: 20),
      headers: {
        'Content-Type': 'application/json',
        'x-device-key': _deviceKey!,
      },
    ));
  }
}