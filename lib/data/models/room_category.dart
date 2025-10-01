class RoomCategory {
  final String type;
  final int priceNgn;
  final List<String> rooms;

  RoomCategory({
    required this.type,
    required this.priceNgn,
    required this.rooms,
  });

  // A "factory constructor" that creates a RoomCategory from a Map
  factory RoomCategory.fromMap(Map<String, dynamic> map) {
    return RoomCategory(
      type: map['type'] ?? 'Unknown Type',
      priceNgn: map['price_ngn'] ?? 0,
      // Ensure 'rooms' is treated as a List of Strings
      rooms: List<String>.from(map['rooms'] ?? []),
    );
  }

  int get roomCount => rooms.length;
}