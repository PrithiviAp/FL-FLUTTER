// lib/services/call_state_service.dart
import 'dart:async';
import 'package:phone_state/phone_state.dart';

class CallStateService {
  static StreamSubscription? _sub;
  static bool _inCall = false;
  static String? _currentNumber;

  static void start({
    required Future<void> Function(String? number) onCallStart,
    required Future<void> Function() onCallEnd,
  }) {
    _sub = PhoneState.stream.listen((state) async {
      final isNowInCall = state.status == PhoneStateStatus.CALL_INCOMING ||
          state.status == PhoneStateStatus.CALL_STARTED;
      if (isNowInCall && !_inCall) {
        _inCall = true;
        _currentNumber = state.number;
        await onCallStart(state.number);
      } else if (!isNowInCall && _inCall) {
        _inCall = false;
        await onCallEnd();
        _currentNumber = null;
      }
    });
  }

  static void stop() => _sub?.cancel();
  static bool get inCall => _inCall;
}