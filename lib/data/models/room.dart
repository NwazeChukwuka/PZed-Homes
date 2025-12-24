class Room {
  final String id;
  final String roomNumber;
  final String type;
  String status;

  Room({
    required this.id,
    required this.roomNumber,
    required this.type,
    required this.status,
  });

  factory Room.fromMap(Map<String, dynamic> map) {
    return Room(
      id: map['id'] as String,
      roomNumber: map['room_number'] as String,
      type: map['type'] as String,
      status: map['status'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'room_number': roomNumber,
      'type': type,
      'status': status,
    };
  }
}
