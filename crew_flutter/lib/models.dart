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

class CrewSeat {
  const CrewSeat({
    required this.seatNumber,
    required this.rowNumber,
    required this.column,
    required this.cabinClass,
    required this.seatType,
    required this.occupancyStatus,
    this.requestId,
    this.requestCategory,
    this.requestStatus,
    this.requestUrgency,
  });

  final String seatNumber;
  final int rowNumber;
  final String column;
  final String cabinClass;
  final String seatType;
  final String occupancyStatus;
  final String? requestId;
  final String? requestCategory;
  final String? requestStatus;
  final String? requestUrgency;

  bool get hasRequest => requestId != null;
  bool get isUrgent => requestUrgency == 'urgent';

  factory CrewSeat.fromJson(Map<String, dynamic> json) => CrewSeat(
    seatNumber: json['seat_number']?.toString() ?? '—',
    rowNumber: (json['row_number'] as num?)?.toInt() ?? 0,
    column: json['seat_column']?.toString() ?? '',
    cabinClass: json['cabin_class']?.toString() ?? 'economy',
    seatType: json['seat_type']?.toString() ?? 'middle',
    occupancyStatus: json['occupancy_status']?.toString() ?? 'available',
    requestId: json['request_id']?.toString(),
    requestCategory: json['request_category']?.toString(),
    requestStatus: json['request_status']?.toString(),
    requestUrgency: json['request_urgency']?.toString(),
  );
}

extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
