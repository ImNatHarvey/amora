#!/usr/bin/env node
// Phase 3 acceptance, as a command.
//
//   node supabase/functions/generate-plan/acceptance.mjs
//
// The criterion (docs/00-architecture.md §8) is:
//
//   20 consecutive generations produce zero invalid IDs; every total matches an
//   independent SQL recomputation exactly; second identical request is a cache hit.
//
// This script covers the first and third directly. It cannot do the second on
// its own and deliberately does not try: recomputing totals means reading
// `places` and `transit_fares` and summing them *without* going through
// `cost_generated_plan`, because asking that function to confirm its own
// arithmetic proves nothing. So every plan is written out as JSON and the
// recomputation is run separately against the database — see the note printed
// at the end.
//
// No dependencies. Reads the project URL and anon key from apps/mobile/.env,
// and signs up a throwaway account through the ordinary public auth endpoint —
// the same path the app uses, with no admin credentials involved.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const RUNS = 20;
const OUT_DIR = join(ROOT, '.acceptance');

// --- config ------------------------------------------------------------------

function loadEnv() {
  const raw = readFileSync(join(ROOT, 'apps', 'mobile', '.env'), 'utf8');
  const env = {};
  for (const line of raw.split(/\r?\n/)) {
    const match = /^([A-Z_]+)=(.*)$/.exec(line.trim());
    if (match) env[match[1]] = match[2].trim();
  }
  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) {
    fail('apps/mobile/.env is missing SUPABASE_URL or SUPABASE_ANON_KEY.');
  }
  return env;
}

/**
 * Ends the run with a status, without calling process.exit().
 *
 * `process.exit()` tears the process down while fetch's keep-alive sockets are
 * still open, which on Windows trips a libuv assertion — the script "fails" with
 * a C-level crash and exit 127 instead of the code it meant to return. Setting
 * `exitCode` lets Node drain and exit on its own with the right status.
 */
function stop(code, message) {
  if (message) console.error(message);
  process.exitCode = code;
  return null;
}

function fail(message) {
  throw new Error(message);
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * The free tier allows **5 requests per minute per model** — measured during
 * the Phase 3b acceptance run, which came back with
 * `quotaValue: "5", quotaId: GenerateRequestsPerMinutePerProjectPerModel-FreeTier`.
 *
 * 13 seconds is ~4.6/minute, just inside it. Unspaced, the run starts returning
 * 429 partway through and the failure reads as "the model produced an invalid
 * plan" rather than "we asked too fast" — which is the worst kind of result,
 * because it sends you looking at the prompt.
 *
 * 503 is retried too: that is Gemini reporting its own overload, not a verdict
 * on the request.
 */
const GAP_MS = 13000;

async function throttled(call, label) {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    await sleep(GAP_MS);
    const result = await call();
    if (result.status !== 429 && result.status !== 503) return result;

    console.log(
      `    (${result.status} on ${label} — backing off, attempt ${attempt + 1}/3)`,
    );
    await sleep(35000);
  }
  return call();
}

// --- the request under test --------------------------------------------------
//
// Budget and time vary across runs on purpose. Twenty identical requests would
// be one generation and nineteen cache hits, which would prove the cache works
// and say nothing about whether the model stays inside the candidate set.

function requestFor(run) {
  const budgets = [20000, 30000, 40000, 60000, 80000];
  // Saturday evening through Sunday afternoon, in two-hour steps.
  const start = Date.parse('2026-08-08T09:00:00Z');
  return {
    city: 'Bocaue',
    budget_php_cents: budgets[run % budgets.length],
    planned_for: new Date(start + (run % 10) * 2 * 3600_000).toISOString(),
    origin_area: 'Poblacion',
    origin_lat: 14.7966,
    origin_lng: 120.9268,
    party_size: 2,
  };
}

async function main() {
  const env = loadEnv();
  const fn = `${env.SUPABASE_URL}/functions/v1/generate-plan`;

  // --- is the secret set? ----------------------------------------------------
  // Checked first, with an unauthenticated call. It fails on the missing key
  // before it touches auth or the database, so nothing is created if we stop
  // here — no throwaway user for a run that cannot proceed.
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
      '\n  BLOCKED — Phase 3 acceptance cannot run yet.\n\n' +
        `  ${body.error ?? 'GEMINI_API_KEY is not set.'}\n\n` +
        '  Set it, then run this again:\n' +
        '    npx supabase login\n' +
        '    npx supabase secrets set GEMINI_API_KEY=... \\\n' +
        '      --project-ref <your-project-ref>\n\n' +
        '  Or: dashboard > Project Settings > Edge Functions > Secrets.\n',
    );
  }

  // --- a throwaway account ---------------------------------------------------
  const email = `amora-acceptance+${Date.now()}@example.com`;
  const password = `acc-${Math.random().toString(36).slice(2)}-${Date.now()}`;

  const signup = await fetch(`${env.SUPABASE_URL}/auth/v1/signup`, {
    method: 'POST',
    headers: { apikey: env.SUPABASE_ANON_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const session = await signup.json();
  if (!session.access_token) {
    fail(
      `could not sign up an acceptance user: ${JSON.stringify(session)}\n` +
        '  If this says email confirmation is required, that setting was turned\n' +
        '  back on — expected before real users, but it blocks this script.',
    );
  }
  console.log(`  signed in as ${email}`);

  const generate = (body) =>
    throttled(
      () =>
        fetch(fn, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${session.access_token}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(body),
        }),
      `₱${body.budget_php_cents / 100} ${body.planned_for.slice(0, 16)}`,
    );

  // --- 20 consecutive generations -------------------------------------------
  const results = [];
  let failures = 0;

  for (let run = 0; run < RUNS; run += 1) {
    const body = requestFor(run);
    const started = Date.now();
    const response = await generate(body);
    const payload = await response.json().catch(() => ({}));
    const elapsed = Date.now() - started;

    // 502 is the function refusing to return an unvalidated plan after its one
    // corrective retry. That is the failure this criterion is about.
    const invalid = response.status === 502;
    if (invalid || response.status >= 400) failures += 1;

    results.push({ run, request: body, status: response.status, elapsed, payload });

    const plans = payload.plans?.length ?? 0;
    const flag = response.status >= 400 ? ' <-- FAILED' : '';
    console.log(
      `  run ${String(run + 1).padStart(2)}/${RUNS}  ` +
        `${response.status}  ${String(elapsed).padStart(5)}ms  ` +
        `${plans} plan(s)  ${payload.cache_hit ? 'cache' : 'fresh'}${flag}`,
    );
  }

  // --- the cache -------------------------------------------------------------
  // Run 0 repeated verbatim. It was a miss the first time, so a hit now is the
  // cache doing its job rather than an accident of ordering.
  const repeat = await generate(requestFor(0));
  const repeatPayload = await repeat.json().catch(() => ({}));
  const cacheHit = repeatPayload.cache_hit === true;
  console.log(`\n  repeat of run 1: ${cacheHit ? 'CACHE HIT' : 'MISS'}`);

  // --- write the evidence ----------------------------------------------------
  mkdirSync(OUT_DIR, { recursive: true });
  const out = join(OUT_DIR, 'phase3-acceptance.json');
  writeFileSync(out, JSON.stringify({ email, results, repeat: repeatPayload }, null, 2));

  // --- verdict ---------------------------------------------------------------
  console.log('\n  ---');
  console.log(`  generations:      ${RUNS}`);
  console.log(`  refused/errored:  ${failures}`);
  console.log(`  cache hit:        ${cacheHit ? 'yes' : 'NO'}`);
  console.log(`  evidence:         ${out}`);
  console.log(
    '\n  STILL TO CHECK BY HAND: recompute every total from places and\n' +
      '  transit_fares directly and compare against the payload. Do NOT use\n' +
      '  cost_generated_plan for it — that is the function under test.\n',
  );

  if (failures > 0 || !cacheHit) {
    return stop(
      1,
      `\n  FAILED  ${failures} generation(s) errored; ` +
        `cache hit ${cacheHit ? 'ok' : 'MISSING'}.\n`,
    );
  }
  console.log('  Two of three criteria pass. The third is the SQL check above.\n');
  return null;
}

main().catch((error) => stop(1, `\n  FAILED  ${error.stack ?? error}\n`));
