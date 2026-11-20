import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

class FsService {
  static const _allowedRoots = [
    '/storage/emulated/0',
    '/storage',
  ];

  /// Lists entries in a directory. Returns a JSON-serialisable map.
  static Future<Map<String, dynamic>> list(String path) async {
    if (!_isAllowed(path)) {
      return {'ok': false, 'error': 'Path not allowed'};
    }

    final dir = Directory(path);
    if (!await dir.exists()) {
      return {'ok': false, 'error': 'Not found'};
    }

    try {
      final items = <Map<String, dynamic>>[];
      await for (final e in dir.list(followLinks: false)) {
        final name = p.basename(e.path);
        final isDir = e is Directory;
        int size = 0;
        DateTime? modified;
        try {
          final st = await e.stat();
          size = st.size;
          modified = st.modified;
        } catch (_) {}

        items.add({
          'name': name,
          'path': e.path,
          'isDir': isDir,
          'size': size,
          'modified': modified?.toIso8601String(),
        });
      }

      items.sort((a, b) {
        final aDir = a['isDir'] as bool;
        final bDir = b['isDir'] as bool;
        if (aDir != bDir) return aDir ? -1 : 1;
        return (a['name'] as String)
            .toLowerCase()
            .compareTo((b['name'] as String).toLowerCase());
      });

      return {'ok': true, 'path': path, 'items': items};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// Uploads a file from device storage to the backend.
  /// Returns {ok: bool, error?: String}.
  static Future<Map<String, dynamic>> uploadToBackend({
    required String baseUrl,
    required String deviceKey,
    required String filePath,
    required String uploadTicket,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return {'ok': false, 'error': 'File not found'};
    }

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 120),
        sendTimeout: const Duration(seconds: 180),
      ));

      final formData = FormData.fromMap({
        'uploadTicket': uploadTicket,
        'file': await MultipartFile.fromFile(
          filePath,
          filename: p.basename(filePath),
        ),
      });

      final resp = await dio.post(
        '$baseUrl/api/devices/fs/upload',
        data: formData,
        options: Options(headers: {'x-device-key': deviceKey}),
      );

      if (resp.statusCode != null && resp.statusCode! < 300) {
        return {'ok': true};
      }
      return {'ok': false, 'error': 'HTTP ${resp.statusCode}'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  static bool _isAllowed(String path) {
    final normalized = p.normalize(path);
    return _allowedRoots.any((r) => normalized == r || normalized.startsWith('$r/'));
  }
}