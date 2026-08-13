// The HTTP shape both Edge Functions share.
//
// Extracted in the post-Phase-6 review, and not for tidiness. These four things
// existed twice and had **already drifted**: `generate-plan`'s copy never learned
// about 429 or 503, so on a free tier capped at five requests per minute it
// answered 500 to the most ordinary condition there is. That is the whole reason
// Phase 3's acceptance run failed 11 of 20 — the harness's retry was watching for
// a 429 that had already been flattened.
//
// This repo has now paid for the same mistake four times: party size in two
// files, `_pesos` in two screens, `_apply`'s body in two methods, and this. Every
// one was found late, and every one needed a single rule to have two homes.

/**
 * Permissive by design. These functions are called from a Flutter app rather
 * than a browser, so an origin allowlist would constrain nobody who matters —
 * and both functions require a valid JWT before doing anything, which is the
 * check that actually decides who may call them.
 */
export const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

/** A JSON response with CORS attached. */
export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'content-type': 'application/json' },
  });
}

/**
 * A failure that came from Gemini rather than from us, carrying its status.
 *
 * Without it a handler's catch flattens every upstream problem to a 500, and a
 * caller cannot tell "you asked too fast, wait" from "this is broken". On a free
 * tier limited to **5 requests per minute per model** — measured from a 429 body,
 * not assumed — that distinction is the difference between a retry and a bug
 * report.
 *
 * The device sees this too, but only since the post-Phase-6 review: Dart's
 * `functions_client.invoke` throws on any non-2xx rather than returning the body,
 * and `guard` had no clause for it, so every status here was reaching users as
 * "check your connection". Passing a status through is only worth anything if
 * something reads it.
 */
export class UpstreamError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
    this.name = 'UpstreamError';
  }
}

/**
 * The response for a project with no Gemini key.
 *
 * Loud and specific: a missing key is a setup step, not a bug, and the message
 * should name the step. Served as a **503** — which is why `guard` reads the body
 * before it reads the status, since a 503 otherwise reads as "the model is busy"
 * and buries the one instruction that would fix it.
 */
export function missingKeyResponse(): Response {
  return json({
    error: 'GEMINI_API_KEY is not set on this project. Add it with: ' +
      'supabase secrets set GEMINI_API_KEY=... (get a free key at ' +
      'https://aistudio.google.com/apikey)',
  }, 503);
}
