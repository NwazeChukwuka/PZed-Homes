class Profile {
  final String id;
  final String? fullName;
  final List<String> roles;
  /// Monthly gross salary in kobo (prefill / HR config only; financial totals use approved payroll rows).
  final int? monthlySalary;

  Profile({
    required this.id,
    this.fullName,
    required this.roles,
    this.monthlySalary,
  });

  factory Profile.fromMap(Map<String, dynamic> map) {
    final raw = map['monthly_salary'];
    final monthlySalary = raw == null
        ? null
        : (raw is int ? raw : int.tryParse(raw.toString()));
    return Profile(
      id: map['id'] as String,
      fullName: map['full_name'] as String?,
      roles: List<String>.from(map['roles'] ?? []),
      monthlySalary: monthlySalary,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'full_name': fullName,
      'roles': roles,
      if (monthlySalary != null) 'monthly_salary': monthlySalary,
    };
  }
}
