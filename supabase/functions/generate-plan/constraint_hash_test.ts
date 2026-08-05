// Tests for the cache key.
//
//   npx deno test supabase/functions/generate-plan/
//
// The key is the primary cost control (§7 step 2) and it has already been wrong
// once in a way nothing would have caught: it produced a *valid-looking* answer
// from the wrong day. Every test here exists because getting it wrong is silent
// — a bad key does not throw, it just hands someone else's plan back.
//
// Each case is written in both directions where that matters. A key function can
// fail by merging things it should separate (wrong answers) or by separating
// things it should merge (no caching at all, which the free tier cannot afford),
// and a test suite that only checks one direction passes trivially if you make
// every key unique.

import { assertEquals, assertNotEquals } from 'jsr:@std/assert@1';
import { constraintKey, DEFAULT_PARTY_SIZE, type PlanRequest } from './constraint_hash.ts';

const BASE: PlanRequest = {
  city: 'Bocaue',
  budget_php_cents: 20000,
  planned_for: '2026-08-08T10:00:00Z', // Manila Saturday 18:00
  origin_area: 'Poblacion',
  origin_lat: 14.7966,
  origin_lng: 120.9268,
  party_size: 2,
};

const key = (over: Partial<PlanRequest>, version = 1) =>
  constraintKey({ ...BASE, ...over }, version);

Deno.test('the Manila day is read from the Manila instant, not the UTC one', () => {
  // The regression. Manila Sunday 02:00 is UTC Saturday 18:00, so reading the
  // day from UTC called it Saturday — and it collided with Manila Saturday
  // 09:00, which is also "morning" on UTC Saturday. Opening hours are per day,
  // so the loser of that collision got a plan for a day the places may be shut.
  const sundayEarly = key({ planned_for: '2026-08-08T18:00:00Z' });
  const saturdayMorning = key({ planned_for: '2026-08-08T01:00:00Z' });

  assertNotEquals(sundayEarly, saturdayMorning);
});

Deno.test('the same Manila day and bucket still share one entry', () => {
  // The other direction. Manila Saturday 18:00 and 20:30 are the same question,
  // and if they stopped sharing a key the cache would stop paying for itself.
  assertEquals(
    key({ planned_for: '2026-08-08T10:00:00Z' }),
    key({ planned_for: '2026-08-08T12:30:00Z' }),
  );
});

Deno.test('the same clock time on a different weekday is a different question', () => {
  assertNotEquals(
    key({ planned_for: '2026-08-08T10:00:00Z' }), // Manila Sat 18:00
    key({ planned_for: '2026-08-09T10:00:00Z' }), // Manila Sun 18:00
  );
});

Deno.test('budgets round to the nearest ₱50, and far-apart budgets do not', () => {
  // ₱180 and ₱200 on the same evening are the same question. ₱200 and ₱600 are
  // not, and merging them would offer someone places they cannot afford.
  assertEquals(key({ budget_php_cents: 18000 }), key({ budget_php_cents: 20000 }));
  assertNotEquals(key({ budget_php_cents: 20000 }), key({ budget_php_cents: 60000 }));
});

Deno.test('owned resources are order-independent but not content-independent', () => {
  // §9: without a resource fingerprint, two users sharing a budget and location
  // collide and one is handed a plan needing gear they do not own. Order must
  // not matter — the same two people listing the same things in a different
  // order are the same request.
  assertEquals(
    key({ owned_resource_ids: ['a', 'b'] }),
    key({ owned_resource_ids: ['b', 'a'] }),
  );
  assertNotEquals(
    key({ owned_resource_ids: ['a', 'b'] }),
    key({ owned_resource_ids: ['a'] }),
  );
});

Deno.test('a catalogue change invalidates every entry', () => {
  // places_version is what stops a corrected price being served stale forever.
  assertNotEquals(key({}, 1), key({}, 2));
});

Deno.test('nearby origins share a grid cell, distant ones do not', () => {
  // ~500 m grid. Two people a street apart are asking the same thing; two
  // barangays apart are not.
  assertEquals(key({ origin_lat: 14.7966 }), key({ origin_lat: 14.7969 }));
  assertNotEquals(key({ origin_lat: 14.7966 }), key({ origin_lat: 14.8503 }));
});

Deno.test('party size defaults consistently when omitted', () => {
  // The cache key and the costing call must agree about how many people an
  // unspecified party has, or a plan is cached under one size and costed for
  // another.
  assertEquals(
    key({ party_size: undefined }),
    key({ party_size: DEFAULT_PARTY_SIZE }),
  );
});

Deno.test('occasion is a coarse bucket, never free text', () => {
  // §9: the user may type "it's our anniversary", but only a bucket reaches the
  // key. Case must not split an entry, and a long utterance must not become a
  // unique key that never hits.
  assertEquals(key({ occasion: 'Anniversary' }), key({ occasion: 'anniversary' }));
  assertEquals(
    key({ occasion: 'anniversary but she has been stressed all week' }),
    key({ occasion: 'anniversary but ' }),
  );
});
