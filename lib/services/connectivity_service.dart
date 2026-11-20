import 'package:connectivity_plus/connectivity_plus.dart';
import 'location_service.dart';

class ConnectivityStatus {
  final bool gpsEnabled;
  final bool internetConnected;
  ConnectivityStatus({required this.gpsEnabled, required this.internetConnected});
}

class ConnectivityService {
  static Future<ConnectivityStatus> check() async {
    final result = await Connectivity().checkConnectivity();
    final connected = result.isNotEmpty && result.first != ConnectivityResult.none;
    final gps = await LocationService.isGpsEnabled();
    return ConnectivityStatus(gpsEnabled: gps, internetConnected: connected);
  }
}