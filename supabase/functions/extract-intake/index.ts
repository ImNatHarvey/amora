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

const GEMINI_KEY = Deno.env.get('GEMINI_API_KEY');
// A secret rather than a constant, for the same reason generate-plan uses one:
// model names change faster than deploys and D8 makes the model a config
// choice. If Gemini answers 404, set this secret rather than editing this file.
const GEMINI_MODEL = Deno.env.get('GEMINI_MODEL') ?? 'gemini-2.5-flash';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

/** Long enough to say anything a date needs; short enough to bound the bill. */
const MAX_UTTERANCE_CHARS = 500;

/**
 * A failure that came from Gemini rather than from us, carrying its status.
 *
 * Without this the handler's catch turns every upstream problem into a 500, and
 * a caller cannot tell "you asked too fast, wait 30 seconds" from "something is
 * broken". That distinction is not cosmetic on a free tier: the limit is **5
 * requests per minute per model**, so 429 is an ordinary condition a client
 * should expect and retry, not an error to report to the user.
 *
 * Found by the Phase 3b acceptance run, whose own retry logic never fired
 * because it was watching for a 429 that had already been flattened to a 500.
 */
class UpstreamError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

async function callGemini(prompt: string): Promise<unknown> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

  const response = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-goog-api-key': GEMINI_KEY! },
    body: JSON.stringify({
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: {
        responseMimeType: 'application/json',
        responseSchema: EXTRACTION_SCHEMA,
        // Near-zero, unlike composition's 0.7. Reading "under 200 tonight" is
        // not a creative task, and variability here would mean the same
        // sentence produced different constraints on different days.
        temperature: 0,
      },
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    if (response.status === 404) {
      throw new UpstreamError(
        404,
        `Gemini rejected model "${GEMINI_MODEL}" (404). Set the GEMINI_MODEL ` +
        `secret to a model available on your key. Body: ${body}`,
      );
    }
    if (response.status === 429) {
      throw new UpstreamError(
        429,
        'Too many requests to the model just now. The free tier allows 5 per ' +
        'minute; try again shortly.',
      );
    }
    if (response.status === 503) {
      throw new UpstreamError(
        503,
        'The model is busy right now. This is temporary — try again shortly.',
      );
    }
    throw new UpstreamError(response.status, `Gemini ${response.status}: ${body}`);
  }

  const data = await response.json();
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) throw new Error(`Gemini returned no content: ${JSON.stringify(data).slice(0, 500)}`);

  return JSON.parse(text);
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...CORS, 'content-type': 'application/json' },
    });

  try {
    if (!GEMINI_KEY) {
      // Loud and specific. A missing key is a setup step, not a bug.
      return json({
        error: 'GEMINI_API_KEY is not set on this project. Add it with: ' +
          'supabase secrets set GEMINI_API_KEY=... (get a free key at ' +
          'https://aistudio.google.com/apikey)',
      }, 503);
    }

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

    const raw = await callGemini(
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
        model: GEMINI_MODEL,
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
