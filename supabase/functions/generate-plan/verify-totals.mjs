#!/usr/bin/env node
// Phase 3's third criterion, as a command.
//
//   node supabase/functions/generate-plan/verify-totals.mjs
//
// The criterion (docs/00-architecture.md §8) is "every total matches an
// independent SQL recomputation exactly", and §8 is explicit that it "must not
// use cost_generated_plan — that is the function being tested". It used to say
// this part was done by hand. It was, twice, and then this was written: hand-
// checking two plans out of fifty-eight is a sample, and the criterion says
// *every*.
//
// What it reads from the acceptance payload is only what the payload cannot fake:
//
//   * the stop SLUG      — a natural key, so the price is looked up fresh
//   * the leg MODE       — walk / jeepney / tricycle
//   * the totals claimed — the thing being checked
//
// Every peso is recomputed from `places.price_min_php_cents` and `transit_fares`,
// fetched over the public REST API with the anon key. `party_price_php_cents`,
// `fare_php_cents` and the totals in the payload are never used as inputs.
//
// `fare_for` is avoided too. It is not the function under test, but it shares the
// per-person/flat rule with it, and a check that reuses the code it is checking is
// not a check.
//
// **The arithmetic is deliberately not in SQL.** A recomputation written in the
// same dialect, with the same joins, in the same engine, can repeat the original's
// mistake; a second implementation in another language cannot repeat it by
// accident. That is also how the first hand-check went wrong — it summed every
// fare row for a barangay pair, not noticing Poblacion↔Turo has both a tricycle
// and a jeepney row, and reported a mismatch that was the check's fault rather
// than the function's.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const EVIDENCE = join(ROOT, '.acceptance', 'phase3-acceptance.json');

function loadEnv() {
  const raw = readFileSync(join(ROOT, 'apps', 'mobile', '.env'), 'utf8');
  const env = {};
  for (const line of raw.split(/\r?\n/)) {
    const match = /^([A-Z_]+)=(.*)$/.exec(line.trim());
    if (match) env[match[1]] = match[2].trim();
  }
  return env;
}

const env = loadEnv();
if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) {
  console.error('apps/mobile/.env is missing SUPABASE_URL or SUPABASE_ANON_KEY.');
  process.exitCode = 2;
} else {
  await main(env);
}

async function rest(env, path) {
  const response = await fetch(`${env.SUPABASE_URL}/rest/v1/${path}`, {
    headers: {
      apikey: env.SUPABASE_ANON_KEY,
      Authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
    },
  });
  if (!response.ok) {
    throw new Error(`${path} -> ${response.status} ${await response.text()}`);
  }
  return response.json();
}

async function main(env) {
  let evidence;
  try {
    evidence = JSON.parse(readFileSync(EVIDENCE, 'utf8'));
  } catch {
    console.error(
      `No evidence at ${EVIDENCE}.\n` +
      'Run node supabase/functions/generate-plan/acceptance.mjs first.',
    );
    process.exitCode = 2;
    return;
  }

  // Both tables are world-readable (§5), so the anon key is enough and no admin
  // credential is involved — the same principle the acceptance harness follows.
  const places = await rest(env, 'places?select=slug,barangay,price_min_php_cents');
  const fares = await rest(
    env,
    'transit_fares?select=from_area,to_area,mode,fare_php_cents,is_per_person',
  );

  const priceOf = new Map(places.map((p) => [p.slug, p.price_min_php_cents]));
  const areaOf = new Map(places.map((p) => [p.slug, p.barangay]));

  /** What the party pays for one leg, or null when no fare is recorded. */
  const fareFor = (fromArea, toArea, mode, party) => {
    if (mode === 'walk') return 0;
    const row = fares.find(
      (f) => f.mode === mode &&
        ((f.from_area === fromArea && f.to_area === toArea) ||
         (f.from_area === toArea && f.to_area === fromArea)),
    );
    // Null is not zero: an unpriced leg is left out of the total rather than
    // counted as free, which is what makes the plan screen say "at least ₱X".
    if (!row) return null;
    return row.is_per_person ? row.fare_php_cents * party : row.fare_php_cents;
  };

  let plans = 0;
  let placesOk = 0;
  let faresOk = 0;
  let totalsOk = 0;
  const problems = [];

  for (const run of evidence.results) {
    const party = run.request.party_size;
    const origin = run.request.origin_area;

    for (const [i, plan] of (run.payload.plans ?? []).entries()) {
      plans += 1;
      const key = `run ${run.run} plan ${i}`;

      let expectedPlaces = 0;
      for (const stop of plan.stops ?? []) {
        const price = priceOf.get(stop.slug);
        if (price === undefined) {
          problems.push(`${key}: slug ${stop.slug} is not in places at all`);
          continue;
        }
        // Per person, times party size (§9). This is the multiplication that made
        // every total wrong by 2x before it was defined.
        expectedPlaces += price * party;
      }

      // Leg N arrives at stop N; leg 1 starts from the request's origin area.
      let expectedFares = 0;
      for (const [j, leg] of (plan.legs ?? []).entries()) {
        const toArea = areaOf.get(plan.stops[j]?.slug);
        const fromArea = j === 0 ? origin : areaOf.get(plan.stops[j - 1]?.slug);
        const fare = fareFor(fromArea, toArea, leg.mode, party);
        if (fare !== null) expectedFares += fare;
      }

      const claimed = plan.totals;
      const expectedTotal = expectedPlaces + expectedFares;

      if (expectedPlaces === claimed.places_php_cents) placesOk += 1;
      else {
        problems.push(
          `${key}: places ${expectedPlaces} vs ${claimed.places_php_cents}`);
      }

      if (expectedFares === claimed.fares_php_cents) faresOk += 1;
      else {
        problems.push(
          `${key}: fares ${expectedFares} vs ${claimed.fares_php_cents}`);
      }

      if (expectedTotal === claimed.total_php_cents) totalsOk += 1;
      else {
        problems.push(
          `${key}: TOTAL ${expectedTotal} vs ${claimed.total_php_cents}`);
      }
    }
  }

  console.log(`\n  plans checked:  ${plans}`);
  console.log(`  places match:   ${placesOk}/${plans}`);
  console.log(`  fares match:    ${faresOk}/${plans}`);
  console.log(`  totals match:   ${totalsOk}/${plans}`);

  if (problems.length === 0) {
    console.log(
      '\n  Every figure recomputed from places and transit_fares, ' +
      'without cost_generated_plan.\n',
    );
  } else {
    console.log(`\n  ${problems.length} problem(s):`);
    for (const problem of problems.slice(0, 25)) console.log(`    ${problem}`);
  }

  process.exitCode = problems.length === 0 ? 0 : 1;
}
