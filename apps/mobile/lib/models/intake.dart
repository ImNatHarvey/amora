/// What a user's sentence reduced to.
///
/// §7 step 1's record, as much of it as language can supply. Four fields —
/// matching exactly what the cache key already consumes, so a conversation
/// introduces nothing new to hash. Owned resources come from the profile rather
/// than from what someone said; party size is fixed by D1.
///
/// **Null is a real answer, not a gap to paper over.** Anything the message did
/// not state stays null, becomes an unfilled chip, and gets asked about. A
/// default the user cannot see costs them their evening; a chip costs them a
/// tap (`docs/02-design-system.md` §9).
///
/// There is no field here for a place or an activity, and that is the point:
/// the extraction schema has nowhere to put one, so invariant 1 holds by shape
/// rather than by checking.
class IntakeConstraints {
  const IntakeConstraints({
    this.budgetPhpCents,
    this.plannedForUtc,
    this.originArea,
    this.occasion,
  });

  factory IntakeConstraints.fromMap(Map<String, dynamic> map) =>
      IntakeConstraints(
        budgetPhpCents: map['budget_php_cents'] as int?,
        plannedForUtc: switch (map['planned_for']) {
          final String time => DateTime.tryParse(time)?.toUtc(),
          _ => null,
        },
        originArea: map['origin_area'] as String?,
        occasion: map['occasion'] as String?,
      );

  /// The whole party's budget, in centavos — never per person (§9).
  final int? budgetPhpCents;
  final DateTime? plannedForUtc;

  /// A barangay, validated server-side against `known_areas`. It cannot be a
  /// business name: the validator drops anything that is not an area we can
  /// cost a leg to.
  final String? originArea;

  /// `casual` or `special`. A coarse bucket, because free text here would reach
  /// the cache key and fragment it into single-use entries (§9).
  final String? occasion;

  /// What still has to be asked about, in the order worth asking.
  ///
  /// Budget first because it is the primary input of the whole product, then
  /// when, then where from. Occasion is absent deliberately — it is the one
  /// constraint a plan can be composed without, so demanding it would turn a
  /// nicety into a blocker.
  List<IntakeField> get missing => [
        if (budgetPhpCents == null) IntakeField.budget,
        if (plannedForUtc == null) IntakeField.time,
        if (originArea == null) IntakeField.origin,
      ];

  /// True when there is enough to compose a plan.
  bool get isComplete => missing.isEmpty;

  /// True once anything at all has been established.
  ///
  /// This is what tells the screen to stop showing starter chips and start
  /// showing constraint chips. Without it, tapping "Tonight" sets a value that
  /// nothing renders — the starter screen stays up and the tap reads as a
  /// no-op.
  bool get hasAny =>
      budgetPhpCents != null ||
      plannedForUtc != null ||
      originArea != null ||
      occasion != null;

  IntakeConstraints copyWith({
    int? budgetPhpCents,
    DateTime? plannedForUtc,
    String? originArea,
    String? occasion,
  }) =>
      IntakeConstraints(
        budgetPhpCents: budgetPhpCents ?? this.budgetPhpCents,
        plannedForUtc: plannedForUtc ?? this.plannedForUtc,
        originArea: originArea ?? this.originArea,
        occasion: occasion ?? this.occasion,
      );
}

/// The constraints a chip can stand for.
enum IntakeField {
  budget('How much?'),
  time('When?'),
  origin('Starting where?');

  const IntakeField(this.prompt);

  /// What an **unfilled** chip says. A question, never a guess — the design
  /// system is explicit that a constraint the model could not determine appears
  /// as a prompt rather than as a silent default.
  final String prompt;
}
