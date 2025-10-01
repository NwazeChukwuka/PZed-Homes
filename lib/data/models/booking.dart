class Booking {
  final String id;
  final String guestName;
  final String roomNumber;
  final String roomType;
  final DateTime checkInDate;
  final DateTime checkOutDate;
  final String status;
  final List<Map<String, dynamic>> extraCharges;

  Booking({
    required this.id,
    required this.guestName,
    required this.roomNumber,
    required this.roomType,
    required this.checkInDate,
    required this.checkOutDate,
    required this.status,
    required this.extraCharges,
  });

  // Add copyWith method that your UI code expects
  Booking copyWith({
    String? id,
    String? guestName,
    String? roomNumber,
    String? roomType,
    DateTime? checkInDate,
    DateTime? checkOutDate,
    String? status,
    List<Map<String, dynamic>>? extraCharges,
  }) {
    return Booking(
      id: id ?? this.id,
      guestName: guestName ?? this.guestName,
      roomNumber: roomNumber ?? this.roomNumber,
      roomType: roomType ?? this.roomType,
      checkInDate: checkInDate ?? this.checkInDate,
      checkOutDate: checkOutDate ?? this.checkOutDate,
      status: status ?? this.status,
      extraCharges: extraCharges ?? this.extraCharges,
    );
  }

  // Keep your existing fromMap and toMap methods for database operations
  factory Booking.fromMap(Map<String, dynamic> map) {
    return Booking(
      id: map['id'] as String,
      guestName: map['guest_name'] as String, // Add this
      roomNumber: map['room_number'] as String, // Add this
      roomType: map['room_type'] as String, // Add this
      checkInDate: DateTime.parse(map['check_in_date']),
      checkOutDate: DateTime.parse(map['check_out_date']),
      status: map['status'] as String,
      extraCharges: List<Map<String, dynamic>>.from(map['extra_charges'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'guest_name': guestName, // Add this
      'room_number': roomNumber, // Add this
      'room_type': roomType, // Add this
      'check_in_date': checkInDate.toIso8601String(),
      'check_out_date': checkOutDate.toIso8601String(),
      'status': status,
      'extra_charges': extraCharges,
    };
  }
}