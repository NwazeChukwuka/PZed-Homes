class Booking {
  final String id;
  final String guestName;
  final String? roomNumber; // Nullable - room may not be assigned yet
  final String? roomId; // Nullable - room may not be assigned yet
  final String? requestedRoomType; // Room type requested by guest
  final String roomType;
  final DateTime checkInDate;
  final DateTime checkOutDate;
  final String status;
  final List<Map<String, dynamic>> extraCharges;

  Booking({
    required this.id,
    required this.guestName,
    this.roomNumber,
    this.roomId,
    this.requestedRoomType,
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
    String? roomId,
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
      roomId: roomId ?? this.roomId,
      requestedRoomType: requestedRoomType,
      roomType: roomType ?? this.roomType,
      checkInDate: checkInDate ?? this.checkInDate,
      checkOutDate: checkOutDate ?? this.checkOutDate,
      status: status ?? this.status,
      extraCharges: extraCharges ?? this.extraCharges,
    );
  }

  // Keep your existing fromMap and toMap methods for database operations
  factory Booking.fromMap(Map<String, dynamic> map) {
    // Handle both direct map and nested structure from Supabase joins
    final room = map['rooms'] as Map<String, dynamic>?;
    final profile = map['profiles'] as Map<String, dynamic>?;
    
    return Booking(
      id: map['id'] as String,
      guestName: profile?['full_name'] as String? ?? map['guest_name'] as String? ?? 'Unknown',
      roomNumber: room?['room_number'] as String?,
      roomId: map['room_id'] as String?,
      requestedRoomType: map['requested_room_type'] as String?,
      roomType: map['requested_room_type'] as String? ?? 
                room?['type'] as String? ?? 
                map['room_type'] as String? ?? 
                'Unknown',
      checkInDate: DateTime.parse(map['check_in_date'] as String),
      checkOutDate: DateTime.parse(map['check_out_date'] as String),
      status: map['status'] as String? ?? 'Pending Check-in',
      extraCharges: List<Map<String, dynamic>>.from(map['extra_charges'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'guest_name': guestName,
      'room_number': roomNumber,
      'room_id': roomId,
      'requested_room_type': requestedRoomType,
      'room_type': roomType,
      'check_in_date': checkInDate.toIso8601String(),
      'check_out_date': checkOutDate.toIso8601String(),
      'status': status,
      'extra_charges': extraCharges,
    };
  }
}