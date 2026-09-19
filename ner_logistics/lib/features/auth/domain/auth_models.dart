import '../../../mock_data/models.dart';

/// Maps the Supabase `user_role_enum` to the app's [AppRole].
///
/// DB values: field_officer | district_officer | control_room | rider
extension AppRoleDb on AppRole {
  static AppRole? fromDb(String? value) => switch (value) {
        'field_officer' => AppRole.field,
        'district_officer' => AppRole.district,
        'control_room' => AppRole.control,
        'rider' => AppRole.rider,
        _ => null,
      };

  String get dbValue => switch (this) {
        AppRole.field => 'field_officer',
        AppRole.district => 'district_officer',
        AppRole.control => 'control_room',
        AppRole.rider => 'rider',
      };

  String get label => switch (this) {
        AppRole.field => 'Field Officer',
        AppRole.district => 'District Officer',
        AppRole.control => 'Control Room Operator',
        AppRole.rider => 'Logistics Rider',
      };

  String get initials => switch (this) {
        AppRole.field => 'FO',
        AppRole.district => 'DO',
        AppRole.control => 'CO',
        AppRole.rider => 'RD',
      };

  bool get isOfficer => this != AppRole.rider;
}

/// The signed-in user as loaded from `auth.users` + `profiles` + `user_roles`.
class AuthUserProfile {
  final String userId;
  final String email;
  final String fullName;
  final String? officerId;
  final String? phone;
  final String? department;
  final String? organization;
  final String? region;
  final AppRole role;

  /// Display name of the district scoping this user (null for control room).
  final String? districtName;
  final DateTime? lastSignInAt;

  const AuthUserProfile({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.role,
    this.officerId,
    this.phone,
    this.department,
    this.organization,
    this.region,
    this.districtName,
    this.lastSignInAt,
  });

  String get displayName => fullName.trim().isEmpty ? email : fullName.trim();

  /// Short form used in greetings: "P. Lyngdoh" -> "Lyngdoh".
  String get shortName {
    final parts = displayName.split(' ').where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? displayName : parts.last;
  }

  /// Bridges to the legacy [Officer] model used by drawers and profile sheets
  /// so the existing UI renders real account data without a rewrite.
  Officer toOfficer() => Officer(
        name: displayName,
        officerId: officerId ?? email,
        role: role,
        roleLabel: role.label,
        department: department ?? organization ?? 'Janrakshak AI',
        region: region ?? districtName ?? 'North Eastern Region',
        phone: phone ?? '—',
        email: email,
        lastLogin: lastSignInAt == null ? 'This session' : _formatLastLogin(lastSignInAt!),
      );

  static String _formatLastLogin(DateTime t) {
    final local = t.toLocal();
    final now = DateTime.now();
    final sameDay = local.year == now.year && local.month == now.month && local.day == now.day;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return sameDay ? 'Today, $hh:$mm' : '${local.day}/${local.month}/${local.year}, $hh:$mm';
  }
}

/// User-facing authentication failure. `message` is safe to display.
class AuthFailure implements Exception {
  final String message;
  final AuthFailureKind kind;
  const AuthFailure(this.message, {this.kind = AuthFailureKind.other});

  @override
  String toString() => message;
}

enum AuthFailureKind {
  invalidCredentials,
  emailNotConfirmed,
  inactive,
  noRole,
  network,
  rateLimited,
  other,
}
