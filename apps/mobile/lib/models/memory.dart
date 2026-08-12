/// What a couple recorded after an outing.
///
/// One per completed plan (`memories.plan_id` is unique). The reports written
/// beside it — one per stop, feeding §10.5's price correction — are deliberately
/// **not** modelled here: nothing in the app reads them back. They are written
/// for Phase 6b, which reads the whole corpus as the service role, and a Dart
/// type for rows no screen displays would be a type nobody could keep honest.
class Memory {
  const Memory({
    required this.id,
    required this.planId,
    required this.createdAtUtc,
    this.photoPath,
    this.caption,
    this.actualSpendPhpCents,
    this.rating,
    this.planTitle,
    this.plannedForUtc,
  });

  factory Memory.fromMap(Map<String, dynamic> map) {
    // `plans` arrives as an embedded object when the timeline query asks for it,
    // and is absent from complete_plan's return. Both are ordinary: the sheet
    // already knows which plan it just completed.
    final plan = map['plans'] as Map<String, dynamic>?;

    return Memory(
      id: (map['memory_id'] ?? map['id']) as String,
      planId: map['plan_id'] as String,
      photoPath: map['photo_path'] as String?,
      caption: map['caption'] as String?,
      actualSpendPhpCents: map['actual_spend_php_cents'] as int?,
      rating: map['rating'] as int?,
      createdAtUtc: DateTime.parse(map['created_at'] as String).toUtc(),
      planTitle: plan?['title'] as String?,
      plannedForUtc: switch (plan?['planned_for']) {
        final String at => DateTime.tryParse(at)?.toUtc(),
        _ => null,
      },
    );
  }

  final String id;
  final String planId;

  /// Object path in the private `memory-photos` bucket, not a URL. A URL would
  /// be wrong to store: reading is a **signed** URL that expires, so a stored one
  /// would be a link that works today and 404s next week. See
  /// `MemoriesRepository.signedPhotoUrl`.
  ///
  /// Null is ordinary and carries no failure — a completion with no photo still
  /// writes every report, because the correction loop must not depend on someone
  /// having remembered to take a picture.
  final String? photoPath;

  final String? caption;

  /// What the evening really cost the party, in centavos.
  ///
  /// Derived by `complete_plan` from the per-stop figures plus the fares
  /// actually paid — never computed on the device (invariant 3).
  ///
  /// **Null means "we do not know", not zero.** It is null exactly when no stop
  /// figure was recorded at all, and the distinction matters: a fares-only
  /// number presented as the cost of a date would read as a suspiciously cheap
  /// evening rather than as missing information.
  final int? actualSpendPhpCents;

  /// 1–5, or null when they did not say. Not defaulted to 3: an unrated outing
  /// is not an average one.
  final int? rating;

  final DateTime createdAtUtc;

  // --- From the embedded plan, on the timeline query only --------------------

  final String? planTitle;
  final DateTime? plannedForUtc;

  /// Whether there is anything to show but the plan's name.
  ///
  /// A memory with no photo, no caption and no rating is still worth listing —
  /// it says an outing happened — but the card should not render three empty
  /// rows for it.
  bool get isBare => photoPath == null && caption == null && rating == null;
}
