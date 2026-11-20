class CallEntry {
  final String number;
  final String? cachedName;
  final DateTime timestamp;
  final Duration duration;
  final CallKind kind;

  CallEntry({
    required this.number,
    this.cachedName,
    required this.timestamp,
    required this.duration,
    required this.kind,
  });

  Map<String, dynamic> toJson() => {
        'number': number,
        'cachedName': cachedName,
        'capturedAt': timestamp.toIso8601String(),
        'durationSeconds': duration.inSeconds,
        'kind': kind.name,
      };
}

enum CallKind { incoming, outgoing, missed, rejected, unknown }