// The cache key, on its own so it can be tested.
//
// §7 step 2 calls the constraint hash "the primary cost control", and §9 says it
// is what makes a conversational intake affordable later — free text is reduced
// to these constraints *before* anything is hashed, so the key never sees what
// the user typed.
//
// It is also subtle enough to have been wrong once already: the hour was shifted
// into Manila while the day was read from UTC, so Manila Sunday 02:00 and Manila
// Saturday 09:00 produced the same key. That is why this lives in its own module
// rather than inside `index.ts` — importing `index.ts` would start a server,
// which makes the one part of this function that most needs tests the hardest
// part to reach.

/**
 * D1: couples. The server-side twin of Dart's `Party.size`.
 *
 * One constant because this number reaches two different places — the cache key
 * and the costing call — and if a request were ever hashed under one party size
 * and costed for another, the cache would hand back a total for the wrong number
 * of people. It was three separate `?? 2` literals until that was noticed.
 */
export const DEFAULT_PARTY_SIZE = 2;

/**
 * Manila is UTC+8 with no daylight saving, so a fixed offset is exact rather
 * than an approximation. Same rule as `lib/util/manila_time.dart` on the device;
 * stated once here so the two sides cannot drift.
 */
export const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000;

export interface PlanRequest {
  city: string;
  budget_php_cents: number;
  planned_for: string;
  origin_area: string;
  origin_lat: number;
  origin_lng: number;
  owned_resource_ids?: string[];
  party_size?: number;
  occasion?: string;
}

/**
 * The rounded constraint record, as a stable string.
 *
 * Rounding is what makes a cache hit likely at all — ₱180 and ₱200 on a Saturday
 * evening from the same barangay are the same question. Exported separately from
 * the hash so a failing test can show what actually differed, instead of two
 * unequal SHA-256 digests.
 */
export function constraintKey(req: PlanRequest, placesVersion: number): string {
  // ONE Manila instant, and both the hour and the day read from it.
  //
  // Reading the day from the UTC instant instead put it a day behind for every
  // Manila time between midnight and 08:00, collapsing Sunday 02:00 into
  // Saturday. Opening hours are per day, so that served plans composed for days
  // the places are shut — a wrong answer, delivered fast because it was cached.
  const manila = new Date(new Date(req.planned_for).getTime() + MANILA_OFFSET_MS);
  const manilaHour = manila.getUTCHours();
  const timeBucket = manilaHour < 11 ? 'morning' : manilaHour < 16 ? 'afternoon' : 'evening';

  return [
    req.city,
    // Budget to the nearest ₱50.
    Math.round(req.budget_php_cents / 5000) * 5000,
    timeBucket,
    // Day of week matters — a place open Saturday may be shut Tuesday. Read
    // from the Manila instant, not the UTC one.
    manila.getUTCDay(),
    // ~500 m grid. Finer than this and neighbours never share a cache entry.
    req.origin_lat.toFixed(2),
    req.origin_lng.toFixed(2),
    req.party_size ?? DEFAULT_PARTY_SIZE,
    // Sorted fingerprint. Without it two users with the same budget and
    // location but different gear collide, and one gets a plan needing
    // equipment they do not own (§9).
    [...(req.owned_resource_ids ?? [])].sort().join(','),
    // Coarse bucket, never free text.
    (req.occasion ?? 'casual').toLowerCase().slice(0, 16),
    // Invalidates every entry when a price is corrected or a place is
    // quarantined, rather than serving stale totals forever.
    placesVersion,
  ].join('|');
}

/** SHA-256 of [constraintKey], hex encoded. */
export async function constraintHash(
  req: PlanRequest,
  placesVersion: number,
): Promise<string> {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(constraintKey(req, placesVersion)),
  );
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}
