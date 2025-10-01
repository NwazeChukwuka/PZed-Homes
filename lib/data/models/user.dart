// Location: lib/data/models/user.dart
enum AppRole {
  owner,
  manager,
  accountant,
  hr,
  receptionist,
  bartender,
  security,
  laundry_attendant,
  kitchen_staff,
  cleaner,
  purchaser,
  storekeeper,
  housekeeper,
  guest
}

class AppUser {
  final String id;
  final String name;
  final String email;
  final AppRole role;
  final List<AppRole> roles;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.roles,
  });
}