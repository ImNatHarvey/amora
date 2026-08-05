/// One piece of lived experience about a place — the "Reddit layer" (D2).
///
/// This is the part of the catalogue a search cannot produce and a phone call
/// mostly cannot either: that the seating is upstairs with no lift, that it is
/// empty before 4pm, that the aircon only reaches the back room. It is why D2
/// claims to replace the Reddit tab rather than only the Maps tab.
///
/// The table has existed since Phase 0 and had **no renderer until Phase 4**,
/// which quietly undercut that claim for four phases.
class PlaceNote {
  const PlaceNote({
    required this.id,
    required this.body,
    this.sourceLabel,
    this.addedAt,
  });

  factory PlaceNote.fromMap(Map<String, dynamic> map) => PlaceNote(
        id: map['id'] as String,
        body: map['body'] as String,
        sourceLabel: map['source_label'] as String?,
        addedAt: switch (map['added_at']) {
          final String at => DateTime.tryParse(at)?.toUtc(),
          _ => null,
        },
      );

  final String id;
  final String body;

  /// The note's identity within its place, not a category — notes upsert on
  /// `(place, source_label)`, so two notes on one place need different labels.
  /// Not shown to users; it is a data-entry key.
  final String? sourceLabel;

  /// When it was written. Shown, because a note from two years ago and one from
  /// last week are not equally useful and the reader should be able to tell.
  final DateTime? addedAt;
}
