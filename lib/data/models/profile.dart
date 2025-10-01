// Location: lib/data/models/profile.dart
class Profile {
  final String id;
  final String? fullName;
  final List<String> roles;

  Profile({
    required this.id,
    this.fullName,
    required this.roles,
  });

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      fullName: map['full_name'] as String?,
      roles: List<String>.from(map['roles'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'full_name': fullName,
      'roles': roles,
    };
  }
}
