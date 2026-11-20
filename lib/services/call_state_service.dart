// lib/services/call_state_service.dart
import 'dart:async';
import 'package:call_state_handler/call_state_handler.dart';
import 'package:phone_state/phone_state.dart';

class CallStateService {
  static StreamSubscription? _sub;
  static bool _inCall = false;
  static String? _currentNumber;

  /// Exposed so [TrackingTaskHandler] can guard against double-registration
  /// when the dashboard sends `mic.start` more than once.
  static bool get isListening => _sub != null;

  static void start({
    required Future<void> Function(String? number) onCallStart,
    required Future<void> Function() onCallEnd,
  }) {
    // Idempotent: if already listening, tear down the old subscription first.
    _sub?.cancel();
    _sub = null;
    _inCall = false;
    _currentNumber = null;

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

  static void stop() {
    _sub?.cancel();
    _sub = null;
    _inCall = false;
    _currentNumber = null;
  }

  static bool get inCall => _inCall;
  static String? get currentNumber => _currentNumber;
}
