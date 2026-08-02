/// Times are stored UTC and displayed `Asia/Manila` (CLAUDE.md conventions).
///
/// The Philippines is UTC+8 all year and has had no daylight saving since 1978,
/// so the conversion is a fixed offset rather than a timezone-database lookup.
/// That is why there is no `timezone` package here: it would add a dependency
/// and an asset bundle to express one addition, and D1 scopes this app to a
/// single municipality in a single offset.
///
/// Revisit only if Amora ever leaves the Philippines, which is explicitly not a
/// thing being built (CLAUDE.md, "Explicitly NOT building yet").
library;

/// The fixed offset of `Asia/Manila` from UTC.
const manilaOffset = Duration(hours: 8);

/// [utc] as Manila wall-clock time.
///
/// The result is a `DateTime` whose fields read as Manila local time. It is
/// deliberately *not* marked UTC — its calendar fields are what a person in
/// Bocaue would read off a clock, which is the only thing callers want it for.
DateTime toManila(DateTime utc) =>
    DateTime.fromMillisecondsSinceEpoch(
      utc.toUtc().add(manilaOffset).millisecondsSinceEpoch,
      isUtc: true,
    );

/// Manila wall-clock [local] back to a real UTC instant, ready for the server.
DateTime manilaToUtc(DateTime local) => DateTime.utc(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
    ).subtract(manilaOffset);

/// The three-letter key `opening_hours` uses for [manilaLocal]'s day.
///
/// Matches the keys written by `supabase/seed/csv_to_sql.mjs`. Dart numbers
/// weekdays 1 (Monday) to 7 (Sunday).
String dayKey(DateTime manilaLocal) => const [
      'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun',
    ][manilaLocal.weekday - 1];

/// `2026-08-07 18:00` — plain, unambiguous, and sortable.
///
/// Phase 2's screen is deliberately unstyled, so this is a debugging-grade
/// format rather than a designed one. Phase 4 replaces it.
String formatManila(DateTime manilaLocal) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${manilaLocal.year}-${two(manilaLocal.month)}-${two(manilaLocal.day)} '
      '${two(manilaLocal.hour)}:${two(manilaLocal.minute)}';
}
