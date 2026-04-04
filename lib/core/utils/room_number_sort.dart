/// Numeric-aware ordering for hotel room labels (e.g. 101 before 201; avoids "10" < "2" lexicographic bugs).

int? roomNumberSortKey(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty) return null;
  final direct = int.tryParse(s);
  if (direct != null) return direct;
  final match = RegExp(r'\d+').firstMatch(s);
  if (match != null) return int.tryParse(match.group(0)!);
  return null;
}

/// Compares two room number strings for display lists. Non-numeric labels fall back to lexicographic order after numeric ones.
int compareRoomNumbers(String? a, String? b) {
  final ka = roomNumberSortKey(a);
  final kb = roomNumberSortKey(b);
  if (ka != null && kb != null) {
    final c = ka.compareTo(kb);
    if (c != 0) return c;
  } else if (ka != null) {
    return -1;
  } else if (kb != null) {
    return 1;
  }
  return (a ?? '').compareTo(b ?? '');
}

void sortRoomMapsByNumber(List<Map<String, dynamic>> rooms) {
  rooms.sort((a, b) => compareRoomNumbers(
        a['room_number']?.toString(),
        b['room_number']?.toString(),
      ));
}

void sortRoomNumberStrings(List<String> labels) {
  labels.sort(compareRoomNumbers);
}
