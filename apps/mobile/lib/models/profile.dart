import 'preferences.dart';

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
    this.companionType,
    this.interests = const {},
    this.usualBudgetPhpCents,
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
      companionType: CompanionType.fromSlug(map['companion_type'] as String?),
      // The column is `not null default '{}'`, so the null branch is only for
      // a row selected before this migration — or a partial select.
      // An unrecognised slug is dropped rather than throwing: it means the row
      // was written by a newer build, and a downgrade must not strand the
      // profile behind a parse error.
      interests: switch (map['interests']) {
        final List<dynamic> values => {
            for (final slug in values) ?Interest.fromSlug(slug as String),
          },
        _ => const <Interest>{},
      },
      usualBudgetPhpCents: (map['usual_budget_php_cents'] as num?)?.toInt(),
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

  /// Who the user usually plans with. Null until they say.
  final CompanionType? companionType;

  /// Categories to rank activities by. **Empty means no preference**, and must
  /// return the same activities as every interest selected — the ordering
  /// changes, the set never does.
  final Set<Interest> interests;

  /// A default for the intake budget chip, for the whole party. Never a cap.
  final int? usualBudgetPhpCents;

  bool get hasCity => (city ?? '').isNotEmpty;

  bool get isOnboarded => onboardedAt != null;

  /// Whether anything has been expressed. Used to decide between "set your
  /// preferences" and "edit them", never to gate a screen — preferences are
  /// always optional.
  bool get hasPreferences =>
      companionType != null ||
      interests.isNotEmpty ||
      usualBudgetPhpCents != null;
}
