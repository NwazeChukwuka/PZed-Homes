class RoomCategory {
  final String type;
  final int priceNgn;
  final List<String> rooms;
  final List<String> images;

  RoomCategory({
    required this.type,
    required this.priceNgn,
    required this.rooms,
    List<String>? images,
  }) : images = images ?? [
          'assets/images/PZED logo.png', // Default image if none provided
        ];

  // A "factory constructor" that creates a RoomCategory from a Map
  factory RoomCategory.fromMap(Map<String, dynamic> map) {
    return RoomCategory(
      type: map['type'] ?? 'Unknown Type',
      priceNgn: map['price_ngn'] ?? 0,
      // Ensure 'rooms' is treated as a List of Strings
      rooms: List<String>.from(map['rooms'] ?? []),
      images: map['images'] != null ? List<String>.from(map['images']) : null,
    );
  }

  int get roomCount => rooms.length;
}