/// The vocabulary the preferences screen offers, kept beside the model rather
/// than inside the widget so retrieval and the picker cannot drift apart.
///
/// See `docs/02-design-system.md` §10.2 for the specification and
/// `docs/00-architecture.md` §11 for why companion type is stored wider than it
/// is offered.
library;

/// Who the user usually plans with.
///
/// The database permits all five (`profiles.companion_type`'s check
/// constraint). **Only [partner] is offered**, because everything past it is
/// persona expansion — `CLAUDE.md`'s not-building list names "families and solo
/// personas" and §11 defers it. The column is wide so that widening the persona
/// later is a change to [offered] rather than a migration.
enum CompanionType {
  partner('partner', 'My partner'),
  friends('friends', 'Friends'),
  family('family', 'Family'),
  solo('solo', 'Just me'),
  group('group', 'A group');

  const CompanionType(this.slug, this.label);

  final String slug;
  final String label;

  /// What the picker actually shows. One entry, deliberately.
  static const offered = [partner];

  static CompanionType? fromSlug(String? slug) {
    if (slug == null) return null;
    for (final value in values) {
      if (value.slug == slug) return value;
    }
    // An unknown slug is a value written by a newer build. Treated as unset
    // rather than crashing, so a downgrade does not strand the profile.
    return null;
  }
}

/// An interest the user can express.
///
/// **The slug is an `activities.category` value, not a separate vocabulary.**
/// That is the point: `retrieve_activities` ranks by `category`, so an interest
/// that mapped to no category could not change a single result. Offering one
/// would repeat the dead-weight problem the resource catalogue just had, where
/// 18 of 30 rows were required by no activity.
///
/// Finer interests than a category — photography, films — need an
/// `activities.tags` column to rank against. That is a real feature, not a
/// relabelling of this one.
enum Interest {
  outdoor('outdoor', 'Outdoors and nature'),
  food('food', 'Food and coffee'),
  cooking('cooking', 'Cooking together'),
  diy('diy', 'Arts and crafts'),
  fitness('fitness', 'Sports and fitness'),
  music('music', 'Music'),
  indoor('indoor', 'Games and staying in');

  const Interest(this.slug, this.label);

  /// Matches `activities.category`.
  final String slug;
  final String label;

  static Interest? fromSlug(String slug) {
    for (final value in values) {
      if (value.slug == slug) return value;
    }
    return null;
  }
}

/// The amounts the "usual budget" picker offers, in centavos.
///
/// Amounts rather than bands, because the value's only job is to **prefill the
/// intake budget chip**, and a band cannot prefill anything without silently
/// picking a number from inside itself. Stored as what it means.
///
/// ₱0 is first and is a real answer (§9). There is no top band: the picker is a
/// shortcut, never a cap, and the budget sheet takes any number typed.
const usualBudgetOptionsPhpCents = <int>[0, 20000, 50000, 100000, 200000];
