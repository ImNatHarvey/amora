// extract-intake — §7 step 0, in a Supabase Edge Function.
//
// The second and last place Gemini is called. It is deliberately the *smaller*
// of the two: it receives no candidate rows at all, so unlike generate-plan
// there is nothing here for the model to leak. What makes it safe is the shape
// of what it may return, not what it is shown — see `extraction.ts`, which
// holds the schema, the validator and the reasoning.
//
// This function therefore reads no place facts, does no money arithmetic beyond
// passing a budget through, and decides nothing about what is affordable. It
// turns one sentence into at most four values, and asks about the rest.
//
// A separate function rather than a branch inside generate-plan because the two
// have nothing in common but the vendor: different prompt, different schema,
// different failure mode, and this one must stay cheap enough to run on every
// new phrasing.
//
// The Gemini key lives in Edge Function secrets and never reaches the device
// (invariant 4).

import { createClient } from 'jsr:@supabase/supabase-js@2';
import {
  buildExtractionPrompt,
  EXTRACTION_SCHEMA,
  type IntakeConstraints,
  utteranceHash,
  validateExtraction,
} from './extraction.ts';
import { callGemini } from '../_shared/gemini.ts';
import { CORS, json, missingKeyResponse, UpstreamError } from '../_shared/http.ts';

const GEMINI_KEY = Deno.env.get('GEMINI_API_KEY');
/**
 * Extraction gets its **own** model, defaulting to a smaller one than
 * composition uses.
 *
 * Two reasons, and the second is why the *default* differs rather than just the
 * knob existing:
 *
 *   1. **They are different tasks.** Composing three costed plans from thirty
 *      candidate rows is a judgement call. Reading "under 200 tonight" into
 *      four typed fields at `temperature: 0` is mechanical — the schema does
 *      the constraining, not the model's cleverness.
 *   2. **`gemini-2.5-flash` is heavily contended on the free tier.** The Phase
 *      3b acceptance run could not complete twenty extractions: fresh calls
 *      kept returning 503 "high demand" through three backoffs, on top of the
 *      five-requests-per-minute cap. `flash-lite` has a higher limit and far
 *      less queueing.
 *
 * `EXTRACT_MODEL` overrides it. It deliberately does **not** fall back to
 * `GEMINI_MODEL`: that secret may already be set to `gemini-2.5-flash`, and
 * chaining to it would quietly hand extraction the contended model back and
 * make this split do nothing. Two tasks, two settings, no shared default. D8
 * makes the model a config choice; this makes it a per-task one.
 *
 * If Gemini answers 404, set `EXTRACT_MODEL` rather than editing this file.
 */
const MODEL_SECRET = 'EXTRACT_MODEL';
const EXTRACT_MODEL = Deno.env.get(MODEL_SECRET) ?? 'gemini-2.5-flash-lite';

/** Long enough to say anything a date needs; short enough to bound the bill. */
const MAX_UTTERANCE_CHARS = 500;

/** Reads one sentence into four typed fields. `temperature` is 0. */
function extract(prompt: string) {
  return callGemini<unknown>({
    model: EXTRACT_MODEL,
    modelSecret: MODEL_SECRET,
    apiKey: GEMINI_KEY!,
    prompt,
    schema: EXTRACTION_SCHEMA,
    // Near-zero, unlike composition's 0.7. Reading "under 200 tonight" is not a
    // creative task, and variability here would mean the same sentence produced
    // different constraints on different days.
    temperature: 0,
  });
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  try {
    if (!GEMINI_KEY) return missingKeyResponse();

    const authorization = request.headers.get('Authorization');
    if (!authorization) return json({ error: 'Missing Authorization header.' }, 401);

    const asUser = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authorization } } },
    );
    const { data: { user } } = await asUser.auth.getUser();
    if (!user) return json({ error: 'Not signed in.' }, 401);

    // Service role: intake_cache is server infrastructure with RLS on and no
    // policies, exactly like plan_cache, so a device cannot reach it.
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const body = await request.json() as { utterance?: string; city?: string };
    const utterance = (body.utterance ?? '').trim();
    if (utterance === '') return json({ error: 'Nothing to read.' }, 400);
    if (utterance.length > MAX_UTTERANCE_CHARS) {
      return json({ error: 'That is longer than this can read.' }, 400);
    }

    const hash = await utteranceHash(utterance);

    // --- cache -------------------------------------------------------------
    // Keyed on normalised text, never on the text itself: the sentence is not
    // stored, only its digest and what it reduced to.
    const { data: cached } = await admin
      .from('intake_cache')
      .select('id, constraints, hit_count')
      .eq('utterance_hash', hash)
      .maybeSingle();

    if (cached) {
      await admin
        .from('intake_cache')
        .update({ hit_count: (cached.hit_count as number) + 1 })
        .eq('id', cached.id);

      return json({
        constraints: cached.constraints as IntakeConstraints,
        cache_hit: true,
        rejected: [],
      });
    }

    // --- extract -----------------------------------------------------------
    // The barangay list is the only database content in the prompt, and it is a
    // closed list of legal values rather than anything to suggest. It is also
    // what the validator checks against, so what the model is told and what its
    // answer is measured against are the same list by construction.
    const { data: areaRows, error: areaError } = await admin
      .rpc('known_areas', { p_city: body.city ?? 'Bocaue' });
    if (areaError) throw areaError;

    const knownAreas = (areaRows ?? []).map((r: { area: string }) => r.area);

    const raw = await extract(
      buildExtractionPrompt(utterance, knownAreas, new Date().toISOString()),
    );
    const { constraints, rejected } = validateExtraction(raw, knownAreas);

    // Rejections are expected on adversarial input and are not errors — the
    // field becomes null, which becomes a question. Logged because a *pattern*
    // of them is the signal worth having, the same reasoning as
    // PLAN_REJECTED in generate-plan. Free-tier log retention is short, so
    // copy anything worth keeping past a day.
    if (rejected.length > 0) {
      console.error('INTAKE_REJECTED', JSON.stringify({
        model: EXTRACT_MODEL,
        rejected,
        // The utterance is NOT logged. It is user text, and the whole design
        // rests on it never being stored.
        utterance_hash: hash,
      }));
    }

    await admin.from('intake_cache').insert({
      utterance_hash: hash,
      constraints,
      hit_count: 0,
    });

    return json({ constraints, cache_hit: false, rejected });
  } catch (error) {
    console.error('EXTRACT_FAILED', error instanceof Error ? error.message : String(error));

    // Pass an upstream status through rather than flattening it to 500, so a
    // caller can distinguish "wait and retry" from "this is broken".
    if (error instanceof UpstreamError) {
      return json({ error: error.message }, error.status);
    }
    return json({
      error: error instanceof Error ? error.message : 'Extraction failed.',
    }, 500);
  }
});
