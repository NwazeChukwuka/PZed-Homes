enum AppRole {
  owner,
  manager,
  supervisor,
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
  it_admin,
  guest
}

class AppUser {
  final String id;
  final String name;
  final String email;
  final AppRole role;
  final List<AppRole> roles;
  final List<String> permissions;
  final String? department;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.roles,
    required this.permissions,
    this.department,
  });
}