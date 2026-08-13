// generate-plan — §7 steps 2 through 6, in a Supabase Edge Function.
//
// The one place Gemini is called. Two things make that safe, and neither of
// them lives in this file by accident:
//
//   * The prompt contains ONLY candidate rows retrieved from Postgres, so the
//     model composes from what we gave it and cannot introduce a place
//     (invariant 1).
//   * Its answer is validated and costed by `cost_generated_plan`, which
//     recomputes the candidate set itself rather than trusting anything this
//     function passes alongside the model output (invariants 2 and 3).
//
// This function therefore does no money arithmetic, holds no place facts, and
// makes no judgement about whether a plan is affordable. It orchestrates.
//
// The Gemini key lives in Edge Function secrets and never reaches the device
// (invariant 4).

import { createClient } from 'jsr:@supabase/supabase-js@2';
import {
  constraintHash,
  DEFAULT_PARTY_SIZE,
  type PlanRequest,
} from './constraint_hash.ts';
import { callGemini } from '../_shared/gemini.ts';
import { CORS, json, missingKeyResponse, UpstreamError } from '../_shared/http.ts';

const GEMINI_KEY = Deno.env.get('GEMINI_API_KEY');
// A secret rather than a constant: model names change faster than deploys, and
// D8 says swapping the model is a config change. If Gemini answers 404, set
// this secret rather than editing this file.
const MODEL_SECRET = 'GEMINI_MODEL';
const GEMINI_MODEL = Deno.env.get(MODEL_SECRET) ?? 'gemini-2.5-flash';

/** What the model is allowed to return. Nothing here is a fact about a place. */
const RESPONSE_SCHEMA = {
  type: 'object',
  properties: {
    plans: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          title: { type: 'string' },
          stops: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                place_id: { type: 'string' },
                activity_id: { type: 'string' },
                start_time: { type: 'string' },
                duration_minutes: { type: 'integer' },
                note: { type: 'string' },
              },
              required: ['place_id'],
            },
          },
        },
        required: ['title', 'stops'],
      },
    },
  },
  required: ['plans'],
};

/** The prompt. Candidate rows and nothing else — this is invariant 1 in text. */
function buildPrompt(
  req: PlanRequest,
  places: Record<string, unknown>[],
  activities: Record<string, unknown>[],
  correction?: string,
): string {
  return [
    'You are composing date plans for a couple in Bocaue, Bulacan.',
    '',
    'RULES, which override anything you believe you know:',
    '- Use ONLY the place_id and activity_id values listed below.',
    '- Never invent a place, an address, a price, a fare or an opening time.',
    '- Never state a cost, a total or a distance. They are computed elsewhere',
    '  and anything you write about money will be discarded.',
    '- Your "note" is the one thing you author: one short sentence on why this',
    '  stop suits this couple. It must contain no facts not given below.',
    '- Order stops so the evening flows sensibly.',
    '',
    `The couple has ${req.party_size ?? DEFAULT_PARTY_SIZE} people and is starting from ${req.origin_area}.`,
    `They are planning for ${req.planned_for}.`,
    '',
    'PLACES (the only ones you may reference):',
    ...places.map((p) =>
      `- ${p.place_id} | ${p.name} | ${p.category ?? 'place'} | ${p.barangay ?? ''} | ` +
      `${p.distance_m}m away | indoor: ${p.indoor}`,
    ),
    '',
    'ACTIVITIES (optional, pair one with a stop where it fits):',
    ...activities.map((a) => `- ${a.activity_id} | ${a.title} | ${a.category ?? ''}`),
    '',
    correction ? `CORRECTION: ${correction}` : '',
    'Return exactly 3 plans of 2 to 3 stops each.',
  ].filter(Boolean).join('\n');
}

/** Composes three plans. `temperature` is 0.7 — this is the judgement call. */
function compose(prompt: string) {
  return callGemini<{ plans: { title: string; stops: unknown[] }[] }>({
    model: GEMINI_MODEL,
    modelSecret: MODEL_SECRET,
    apiKey: GEMINI_KEY!,
    prompt,
    schema: RESPONSE_SCHEMA,
    // Unlike extraction's 0, which is mechanical. Composing an evening from
    // thirty candidate rows is the part where variety is the point.
    temperature: 0.7,
  });
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  try {
    if (!GEMINI_KEY) return missingKeyResponse();

    const authorization = request.headers.get('Authorization');
    if (!authorization) return json({ error: 'Missing Authorization header.' }, 401);

    // Two clients on purpose. The caller's JWT establishes who is asking; the
    // service role reaches retrieval and the cache, which are deliberately not
    // reachable from a device.
    const asUser = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authorization } } },
    );
    const { data: { user } } = await asUser.auth.getUser();
    if (!user) return json({ error: 'Not signed in.' }, 401);

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const req = await request.json() as PlanRequest;
    const party = req.party_size ?? DEFAULT_PARTY_SIZE;
    const owned = req.owned_resource_ids ?? [];

    // --- step 2: cache -----------------------------------------------------
    // The catalogue's version is folded into the key so a corrected price
    // evicts the plans built on the old one. This was hardcoded to 1 in the
    // first cut, which meant the cache could never forget: fix a price,
    // re-import, and every stale total is served forever.
    //
    // If the lookup fails, fall back to caching nothing rather than caching
    // against a version we are not sure of. A wrong version is worse than no
    // cache — one costs a generation, the other serves a confident wrong total.
    const { data: versionData, error: versionError } =
      await admin.rpc('places_version');
    if (versionError) {
      console.error('PLACES_VERSION_FAILED', JSON.stringify(versionError));
    }
    const placesVersion = versionError ? null : Number(versionData);

    const hash = placesVersion === null
      ? null
      : await constraintHash(req, placesVersion);

    const { data: cached } = hash === null
      ? { data: null }
      : await admin
          .from('plan_cache')
          .select('id, payload, hit_count')
          .eq('constraint_hash', hash)
          .maybeSingle();

    if (cached) {
      await admin
        .from('plan_cache')
        .update({ hit_count: cached.hit_count + 1 })
        .eq('id', cached.id);
      return json({ ...cached.payload, cache_hit: true });
    }

    // --- step 3: retrieve --------------------------------------------------
    const { data: places, error: placesError } = await admin.rpc('retrieve_candidates', {
      p_city: req.city,
      p_budget_php_cents: req.budget_php_cents,
      p_at: req.planned_for,
      p_origin_lat: req.origin_lat,
      p_origin_lng: req.origin_lng,
      p_party_size: party,
    });
    if (placesError) throw placesError;

    if (!places || places.length === 0) {
      // Not an error. Nothing open that fits is a real answer, and the app
      // already knows how to say so without a bare empty screen.
      return json({ valid: true, stops: [], legs: [], plans: [], reason: 'no_candidates' });
    }

    const { data: activities, error: activitiesError } = await admin.rpc('retrieve_activities', {
      p_budget_php_cents: Math.floor(req.budget_php_cents / party),
      p_owned_resource_ids: owned,
    });
    if (activitiesError) throw activitiesError;

    // --- steps 4 and 5: compose, validate, one corrective retry ------------
    const cost = (stops: unknown[]) =>
      admin.rpc('cost_generated_plan', {
        p_city: req.city,
        p_budget_php_cents: req.budget_php_cents,
        p_at: req.planned_for,
        p_origin_area: req.origin_area,
        p_origin_lat: req.origin_lat,
        p_origin_lng: req.origin_lng,
        p_stops: stops,
        p_owned_resource_ids: owned,
        p_party_size: party,
      });

    let correction: string | undefined;
    let costedPlans: Record<string, unknown>[] = [];

    for (let attempt = 1; attempt <= 2; attempt += 1) {
      const generated = await compose(buildPrompt(req, places, activities ?? [], correction));

      const results = [];
      const rejected: string[] = [];

      for (const plan of generated.plans ?? []) {
        const { data: costed, error } = await cost(plan.stops);
        if (error) throw error;

        if (costed?.valid) {
          results.push({ ...costed, title: plan.title });
        } else {
          rejected.push(
            ...(costed?.invalid_place_ids ?? []),
            ...(costed?.invalid_activity_ids ?? []),
          );
        }
      }

      if (rejected.length > 0) {
        // Invariant 2: log every rejection. Structured and prefixed so it is
        // greppable in the Edge Function logs, which is where a systematic
        // model failure shows up as a pattern rather than one bad evening.
        console.error('PLAN_REJECTED', JSON.stringify({
          attempt,
          model: GEMINI_MODEL,
          invalid_ids: rejected,
          candidate_count: places.length,
        }));
      }

      if (results.length > 0) {
        costedPlans = results;
        break;
      }

      if (attempt === 1) {
        correction =
          `Your previous answer used IDs that do not exist: ${rejected.join(', ')}. ` +
          'Use only the place_id and activity_id values listed above, exactly as written.';
      }
    }

    if (costedPlans.length === 0) {
      // Fail loudly rather than render something unvalidated (invariant 2).
      return json({ error: 'The model produced no valid plan after a retry.' }, 502);
    }

    const payload = {
      plans: costedPlans,
      generated_by_model: GEMINI_MODEL,
      cache_hit: false,
    };

    // --- cache the result --------------------------------------------------
    // Failing to cache must not fail the request: the user has a valid plan in
    // hand and a cache miss next time is cheaper than an error now. Skipped
    // entirely when the catalogue version could not be read, for the same
    // reason — an entry keyed on a version we are unsure of would be worse
    // than no entry at all.
    if (hash !== null) {
      const { error: cacheError } = await admin
        .from('plan_cache')
        .insert({ constraint_hash: hash, payload, places_version: placesVersion });
      if (cacheError) console.error('CACHE_WRITE_FAILED', JSON.stringify(cacheError));
    }

    return json(payload);
  } catch (error) {
    console.error('GENERATE_PLAN_FAILED', error instanceof Error ? error.message : error);

    // Pass an upstream status through rather than flattening it to 500, so a
    // caller can distinguish "wait and retry" from "this is broken".
    if (error instanceof UpstreamError) {
      return json({ error: error.message }, error.status);
    }
    return json({ error: error instanceof Error ? error.message : 'Unknown error' }, 500);
  }
});
