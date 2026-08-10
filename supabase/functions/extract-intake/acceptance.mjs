#!/usr/bin/env node
// Phase 3b acceptance, as a command.
//
//   node supabase/functions/extract-intake/acceptance.mjs
//
// The criterion (docs/00-architecture.md §8) is:
//
//   a typed request produces correct chips; correcting a chip re-plans; the
//   same request phrased differently is an intake_cache hit; and extraction
//   never yields a place or activity name across 20 varied utterances,
//   including adversarial ones.
//
// This script covers the first, third and fourth. "Correcting a chip re-plans"
// is a UI behaviour and is covered by widget tests instead — a chip correction
// never reaches this function at all, which is the point of it: a chip is
// already a structured value and skips extraction entirely (§7 step 0).
//
// THE FOURTH IS THE ONE THAT MATTERS. It is the direct test of invariant 1 for
// this path, and it is checked literally: every place name and activity title
// in the database is fetched, and the whole JSON response is searched for each.
// Not "origin_area looks plausible" — no name from the catalogue may appear
// anywhere in the output, in any field.
//
// This is a *sample*, and a weaker claim than the unit tests beside it.
// `extraction_test.ts` proves nothing gets through even when the model
// misbehaves; this proves the model usually behaves, against one model version
// on one day. Both are needed and neither replaces the other.
//
// No dependencies. Reads the project URL and anon key from apps/mobile/.env and
// signs up a throwaway account through the ordinary public auth endpoint.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const OUT_DIR = join(ROOT, '.acceptance');

/**
 * Twenty utterances: ten a real couple would type, eight naming places, two
 * saying almost nothing.
 *
 * The adversarial ones are not exotic — "take me to Jollibee" is what people
 * actually say. The requirement is not that the model refuses them, it is that
 * whatever it returns contains no place name. A user naming somewhere we have
 * no row for resolves to a constraint or to a question, never to a suggestion.
 */
const UTTERANCES = [
  // Ordinary.
  'under 200 tonight',
  'we have ₱500 for this Saturday',
  'something cheap this weekend',
  'free date tonight, we have no money',
  "we're in Turo, around ₱300",
  'anniversary dinner, ₱1000',
  'tomorrow afternoon, budget is flexible',
  '₱150 each, tonight',
  'starting from Poblacion around 7pm',
  'birthday surprise this Friday, ₱800',

  // Naming places. None of these may produce a name in the output.
  'take me to Starbucks in Manila',
  'that café on the highway',
  'plan my Cebu trip',
  'we want to go to Jollibee',
  'somewhere in Quezon City with ₱400',
  'SM Bulacan this weekend',
  "Aling Nena's carinderia, tonight",
  'the new milk tea place everyone posts about',

  // Almost nothing.
  'hi',
  'plan something nice',
];

/** Proves the cache: same meaning, different words and punctuation. */
const REPHRASINGS = [
  ['under 200 tonight', 'Under ₱200, tonight!'],
  ['plan something nice', '  plan   something nice  '],
];

function loadEnv() {
  const raw = readFileSync(join(ROOT, 'apps', 'mobile', '.env'), 'utf8');
  const env = {};
  for (const line of raw.split(/\r?\n/)) {
    const match = /^([A-Z_]+)=(.*)$/.exec(line.trim());
    if (match) env[match[1]] = match[2].trim();
  }
  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) {
    throw new Error('apps/mobile/.env is missing SUPABASE_URL or SUPABASE_ANON_KEY.');
  }
  return env;
}

/**
 * Ends the run without calling process.exit().
 *
 * `process.exit()` tears the process down while fetch's keep-alive sockets are
 * still open, which on Windows trips a libuv assertion — exit 127 instead of
 * the code it meant to return. Cost twenty minutes once already.
 */
function stop(code, message) {
  if (message) console.error(message);
  process.exitCode = code;
  return null;
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * The free tier allows **5 requests per minute per model** — measured, not
 * assumed: the first run of this script came back with
 * `quotaValue: "5", quotaId: GenerateRequestsPerMinutePerProjectPerModel-FreeTier`.
 *
 * 13 seconds is ~4.6/minute, just inside it. A shorter gap starts returning 429
 * partway through and the failure reads as "the model got it wrong" rather than
 * "we asked too fast", which is the worst kind of test result because it sends
 * you looking at the prompt.
 *
 * 503 is retried too. It is Gemini reporting its own overload, not a verdict on
 * the request, and it hit three of twenty on the first run.
 */
const GAP_MS = 13000;

async function throttled(call, label) {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    await sleep(GAP_MS);
    const result = await call();
    if (result.status !== 429 && result.status !== 503) return result;

    console.log(
      `    (${result.status} on "${label}" — backing off, attempt ${attempt + 1}/3)`,
    );
    await sleep(35000);
  }
  return call();
}

async function main() {
  const env = loadEnv();
  const fn = `${env.SUPABASE_URL}/functions/v1/extract-intake`;

  // Is the secret set? Checked first, unauthenticated, so nothing is created
  // if we stop here — no throwaway user for a run that cannot proceed.
  const probe = await fetch(fn, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
      'Content-Type': 'application/json',
    },
    body: '{}',
  });

  if (probe.status === 503) {
    const body = await probe.json().catch(() => ({}));
    return stop(
      2,
      '\n  BLOCKED — Phase 3b acceptance cannot run yet.\n\n' +
        `  ${body.error ?? 'GEMINI_API_KEY is not set.'}\n\n` +
        '  Dashboard > Project Settings > Edge Functions > Secrets,\n' +
        '  or: npx supabase secrets set GEMINI_API_KEY=... --project-ref <ref>\n',
    );
  }

  // Every name the catalogue knows. Fetched with the anon key through the
  // ordinary REST endpoint, so this reads exactly what a device could read.
  const names = [];
  for (const [table, column] of [['places', 'name'], ['activities', 'title']]) {
    const response = await fetch(
      `${env.SUPABASE_URL}/rest/v1/${table}?select=${column}`,
      { headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: `Bearer ${env.SUPABASE_ANON_KEY}` } },
    );
    const rows = await response.json();
    for (const row of rows) if (row[column]) names.push(row[column]);
  }
  console.log(`  checking against ${names.length} catalogue names`);

  const email = `amora-intake+${Date.now()}@example.com`;
  const password = `acc-${Math.random().toString(36).slice(2)}-${Date.now()}`;
  const signup = await fetch(`${env.SUPABASE_URL}/auth/v1/signup`, {
    method: 'POST',
    headers: { apikey: env.SUPABASE_ANON_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const session = await signup.json();
  if (!session.access_token) {
    throw new Error(
      `could not sign up an acceptance user: ${JSON.stringify(session)}\n` +
        '  If this says email confirmation is required, that setting was turned\n' +
        '  back on — expected before real users, but it blocks this script.',
    );
  }
  console.log(`  signed in as ${email}`);

  const extract = (utterance) =>
    throttled(
      () =>
        fetch(fn, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${session.access_token}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ utterance, city: 'Bocaue' }),
        }).then(async (r) => ({ status: r.status, body: await r.json() })),
      utterance,
    );

  const results = [];
  const leaks = [];
  const failures = [];

  for (const utterance of UTTERANCES) {
    const { status, body } = await extract(utterance);
    if (status !== 200) {
      failures.push(`${utterance} → HTTP ${status}: ${JSON.stringify(body)}`);
      continue;
    }

    // The literal check: no catalogue name may appear anywhere in the response.
    const blob = JSON.stringify(body).toLowerCase();
    for (const name of names) {
      if (blob.includes(name.toLowerCase())) {
        leaks.push(`${utterance} → leaked "${name}" in ${JSON.stringify(body.constraints)}`);
      }
    }

    results.push({ utterance, ...body });
    const c = body.constraints;
    console.log(
      `  ${utterance.padEnd(42).slice(0, 42)} → ` +
        `budget=${c.budget_php_cents ?? '—'} ` +
        `when=${c.planned_for ? c.planned_for.slice(0, 16) : '—'} ` +
        `from=${c.origin_area ?? '—'} ` +
        `occasion=${c.occasion ?? '—'}` +
        (body.rejected?.length ? `  [dropped: ${body.rejected.join(',')}]` : ''),
    );
  }

  // The cache, on rephrasings rather than repeats — a repeat would prove only
  // that the same string hashes the same, which is not the claim.
  const cacheMisses = [];
  for (const [first, second] of REPHRASINGS) {
    await extract(first);
    const { body } = await extract(second);
    if (!body.cache_hit) cacheMisses.push(`"${second}" did not hit the entry for "${first}"`);
    else console.log(`  cache hit: "${second}" reused "${first}"`);
  }

  mkdirSync(OUT_DIR, { recursive: true });
  const out = join(OUT_DIR, 'extract-intake.json');
  writeFileSync(out, JSON.stringify(results, null, 2));

  console.log(`\n  ${results.length}/${UTTERANCES.length} extractions returned 200`);
  console.log(`  written to ${out}`);

  if (failures.length || leaks.length || cacheMisses.length) {
    return stop(
      1,
      '\n  FAILED\n' +
        failures.map((f) => `    request: ${f}`).join('\n') +
        leaks.map((l) => `    LEAK: ${l}`).join('\n') +
        cacheMisses.map((c) => `    cache: ${c}`).join('\n') +
        '\n',
    );
  }

  console.log('\n  PASS — no catalogue name appeared in any extraction,');
  console.log('  and both rephrasings hit the cache.\n');
  return null;
}

main().catch((error) => stop(1, `\n  ERROR: ${error.message}\n`));
