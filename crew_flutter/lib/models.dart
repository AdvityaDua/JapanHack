class DeviceSession {
  const DeviceSession({
    required this.deviceId,
    required this.deviceToken,
    required this.flightId,
  });
  final String deviceId;
  final String deviceToken;
  final String flightId;
}

class CrewRequest {
  const CrewRequest({
    required this.id,
    required this.seat,
    required this.category,
    required this.message,
    required this.urgency,
    required this.status,
    required this.createdAt,
    this.passengerLanguage = 'English',
  });

  final String id;
  final String seat;
  final String category;
  final String? message;
  final String urgency;
  final String status;
  final DateTime createdAt;
  final String passengerLanguage;

  bool get isUrgent => urgency == 'urgent';
  bool get isNew => status == 'created';

  CrewRequest copyWith({String? status}) => CrewRequest(
    id: id,
    seat: seat,
    category: category,
    message: message,
    urgency: urgency,
    status: status ?? this.status,
    createdAt: createdAt,
    passengerLanguage: passengerLanguage,
  );

  factory CrewRequest.fromJson(Map<String, dynamic> json) => CrewRequest(
    id: json['id']?.toString() ?? '',
    seat:
        json['seat_number']?.toString() ??
        json['seat_token']?.toString() ??
        '—',
    category: _titleCase(json['category']?.toString() ?? 'Assistance'),
    message: json['message']?.toString(),
    urgency: json['urgency']?.toString() ?? 'normal',
    status: json['status']?.toString() ?? 'created',
    passengerLanguage: json['passenger_language']?.toString() ?? 'English',
    createdAt:
        DateTime.tryParse(json['created_at']?.toString() ?? '') ??
        DateTime.now(),
  );

  static String _titleCase(String value) => value
      .split(RegExp(r'[_\s]+'))
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
