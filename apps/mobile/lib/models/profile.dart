/// A user's profile row. One per authenticated account, created by the
/// `on_auth_user_created` trigger at signup with everything but `id` null.
class Profile {
  const Profile({
    required this.id,
    this.displayName,
    this.city,
    this.homeLat,
    this.homeLng,
    this.onboardedAt,
  });

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      displayName: map['display_name'] as String?,
      city: map['city'] as String?,
      homeLat: (map['home_lat'] as num?)?.toDouble(),
      homeLng: (map['home_lng'] as num?)?.toDouble(),
      onboardedAt: switch (map['onboarded_at']) {
        final String value => DateTime.parse(value).toUtc(),
        _ => null,
      },
    );
  }

  /// Matches `auth.users.id`.
  final String id;
  final String? displayName;
  final String? city;
  final double? homeLat;
  final double? homeLng;

  /// Set when the resource picker is finished. Null means onboarding is
  /// unfinished — which is not the same as owning nothing.
  final DateTime? onboardedAt;

  bool get hasCity => (city ?? '').isNotEmpty;

  bool get isOnboarded => onboardedAt != null;
}
