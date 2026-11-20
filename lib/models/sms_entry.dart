class SmsEntry {
  final String address;
  final String body;
  final DateTime date;
  final SmsKind kind;

  SmsEntry({
    required this.address,
    required this.body,
    required this.date,
    required this.kind,
  });

  Map<String, dynamic> toJson() => {
        'address': address,
        'body': body,
        'capturedAt': date.toIso8601String(),
        'kind': kind.name,
      };
}

enum SmsKind { inbox, sent }