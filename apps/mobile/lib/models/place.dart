import '../util/manila_time.dart';

/// When a place is open, as stored in `places.opening_hours`.
///
/// The shape is `{"fri": [["18:00", "02:00"]], ...}` — each day holding a list
/// of ranges, written by `supabase/seed/csv_to_sql.mjs`. Days that are absent
/// are closed.
///
/// A range whose closing time is earlier than its opening time wraps past
/// midnight and belongs to the day it *opens*: `fri 18:00-02:00` runs into
/// Saturday morning. Nothing here has to resolve that — `public.is_open_at`
/// already decided whether the place is open before it was ever returned. This
/// type exists only so the screen can show the hours a user can check against
/// the real world.
class OpeningHours {
  const OpeningHours(this._byDay);

  factory OpeningHours.fromMap(Map<String, dynamic> map) {
    return OpeningHours({
      for (final entry in map.entries)
        entry.key: [
          for (final range in entry.value as List)
            (
              opens: (range as List)[0] as String,
              closes: range[1] as String,
            ),
        ],
    });
  }

  final Map<String, List<({String opens, String closes})>> _byDay;

  bool get isEmpty => _byDay.isEmpty;

  /// The ranges recorded for [manilaLocal]'s day, empty when closed.
  List<({String opens, String closes})> on(DateTime manilaLocal) =>
      _byDay[dayKey(manilaLocal)] ?? const [];

  /// `09:00–22:00`, or `09:00–22:00, 14:00–18:00` for a split day.
  ///
  /// Returns null when nothing is recorded for that day, so callers can choose
  /// their own wording rather than being handed an empty string.
  String? describe(DateTime manilaLocal) {
    final ranges = on(manilaLocal);
    if (ranges.isEmpty) return null;
    if (ranges.length == 1 &&
        ranges.first.opens == '00:00' &&
        ranges.first.closes == '24:00') {
      return 'open 24 hours';
    }
    return ranges.map((r) => '${r.opens}–${r.closes}').join(', ');
  }
}

/// A curated place in the local database — the moat (docs D3).
///
/// Read-only to the app in Phase 2. User-submitted places land in Phase 5 and
/// are quarantined by RLS when they do.
class Place {
  const Place({
    required this.id,
    required this.slug,
    required this.name,
    required this.category,
    required this.lat,
    required this.lng,
    required this.priceMinPhpCents,
    this.barangay,
    this.priceMaxPhpCents,
    this.openingHours,
    this.address,
    this.contactNumber,
    this.socialUrl,
    this.notes,
    this.verifiedOn,
    this.verifiedMethod,
  });

  factory Place.fromMap(Map<String, dynamic> map) {
    return Place(
      // `place_id` is what the retrieval RPCs alias it to; `id` is the column's
      // real name. Accepting both means a direct query of `places` — which
      // Phase 4's place detail will do — does not fail on a null cast.
      id: (map['place_id'] ?? map['id']) as String,
      slug: map['slug'] as String,
      name: map['name'] as String,
      category: map['category'] as String,
      barangay: map['barangay'] as String?,
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      priceMinPhpCents: map['price_min_php_cents'] as int,
      priceMaxPhpCents: map['price_max_php_cents'] as int?,
      openingHours: switch (map['opening_hours']) {
        final Map<String, dynamic> hours => OpeningHours.fromMap(hours),
        _ => null,
      },
      // Absent from the retrieval RPCs, present when a place is read on its
      // own for Phase 4's detail screen. Null here means "not selected", not
      // "not recorded" — the detail screen is the only caller that asks.
      address: map['address'] as String?,
      contactNumber: map['contact_number'] as String?,
      socialUrl: map['social_url'] as String?,
      notes: map['notes'] as String?,
      verifiedOn: switch (map['verified_on']) {
        final String date => DateTime.tryParse(date),
        _ => null,
      },
      verifiedMethod: map['verified_method'] as String?,
    );
  }

  final String id;

  /// Stable natural key. Re-importing an edited seed CSV updates this row
  /// rather than inserting a second one.
  final String slug;
  final String name;

  /// `cafe`, `park`, `viewpoint`, `florist`, `market`, ...
  final String category;
  final String? barangay;
  final double lat;
  final double lng;

  /// The cheapest a visit here realistically costs. Zero is a real, common
  /// answer — a park costs nothing, and the design system says never to grey
  /// that out (docs 02 §2).
  final int priceMinPhpCents;
  final int? priceMaxPhpCents;

  /// Null when nothing has been recorded yet. Such a place is never retrieved,
  /// because "currently open" cannot be promised about hours nobody verified.
  final OpeningHours? openingHours;

  // --- Read only by place detail (Phase 4) ----------------------------------
  // Retrieval does not select these, so they are null on a stop inside a plan
  // and populated when the place is opened on its own.

  final String? address;

  /// Both null on every row today — nothing has been collected. The detail
  /// screen must omit them rather than render an empty label, which is why
  /// they are nullable rather than defaulted to an empty string.
  final String? contactNumber;
  final String? socialUrl;

  /// The lived-experience one-liner on the row itself, distinct from the
  /// `place_notes` rows, which are many and dated.
  final String? notes;

  /// When a person established this row, and how — `visited`, `phoned` or
  /// `resident` (`docs/00-architecture.md` §10.4a). Shown to the user as
  /// provenance, because the design system requires a catalogue's weakest rows
  /// to be distinguishable from its strongest (§2).
  final DateTime? verifiedOn;
  final String? verifiedMethod;
}
