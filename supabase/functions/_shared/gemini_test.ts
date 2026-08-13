// The status mapping, which has already been wrong once in each direction.
//
// `generate-plan` had no 429 or 503 branch, so the commonest condition on a free
// tier answered 500 and defeated the acceptance harness's retry. `extract-intake`
// named the wrong secret in its 404. Both were copies of one function that
// nothing tested.
//
// Tested against fabricated `Response`s rather than through `callGemini`, which
// would need either a live API call or a global `fetch` mock. Same reasoning that
// keeps `constraint_hash.ts` and `extraction.ts` out of `index.ts`: the part most
// needing tests should not be the hardest part to reach.
//
// Run with: npx deno@latest test supabase/functions/

import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { upstreamErrorFor } from './gemini.ts';
import { UpstreamError } from './http.ts';

const CALL = { model: 'gemini-2.5-flash-lite', modelSecret: 'EXTRACT_MODEL' };

function failed(status: number, body = 'upstream body'): Response {
  return new Response(body, { status });
}

Deno.test('429 keeps its status, so a caller can retry rather than report a bug', async () => {
  const error = await upstreamErrorFor(failed(429), CALL);

  assertEquals(error.status, 429);
  assertEquals(error instanceof UpstreamError, true);
  // The message has to be usable as-is: since the post-Phase-6 review it reaches
  // the device verbatim through `guard`'s FunctionException clause.
  assertStringIncludes(error.message, 'try again shortly');
});

Deno.test('503 is the model reporting its own overload, not a fault', async () => {
  // Three of twenty on one Phase 3b run. Transient and retried.
  const error = await upstreamErrorFor(failed(503), CALL);

  assertEquals(error.status, 503);
  assertStringIncludes(error.message, 'temporary');
});

Deno.test('404 names the secret THIS caller reads', async () => {
  // The bug this parameter exists to prevent: extract-intake's copy said
  // GEMINI_MODEL, which it deliberately does not consult, so doing what the
  // error said would change nothing.
  const error = await upstreamErrorFor(failed(404), CALL);

  assertEquals(error.status, 404);
  assertStringIncludes(error.message, 'EXTRACT_MODEL');
  // And must NOT name the other one.
  assertEquals(error.message.includes('GEMINI_MODEL'), false);
});

Deno.test('404 for the composer names its own secret instead', async () => {
  // The same function, the other caller. Two assertions in opposite directions,
  // because a mapping that always said "EXTRACT_MODEL" would pass the test above.
  const error = await upstreamErrorFor(
    failed(404),
    { model: 'gemini-2.5-flash', modelSecret: 'GEMINI_MODEL' },
  );

  assertStringIncludes(error.message, 'GEMINI_MODEL');
  assertEquals(error.message.includes('EXTRACT_MODEL'), false);
});

Deno.test('404 quotes the model that was rejected', async () => {
  // Without it the message says a secret is wrong without saying what value it
  // currently holds, which is the one fact needed to fix it.
  const error = await upstreamErrorFor(failed(404), CALL);

  assertStringIncludes(error.message, 'gemini-2.5-flash-lite');
});

Deno.test('an unmapped status passes through with its own code', async () => {
  // 400 from a malformed request, say. Not turned into a 500: the status is the
  // only thing distinguishing our bug from theirs.
  const error = await upstreamErrorFor(failed(400, 'bad schema'), CALL);

  assertEquals(error.status, 400);
  assertStringIncludes(error.message, 'bad schema');
});

Deno.test('the upstream body is carried on unmapped statuses, for the logs', async () => {
  const error = await upstreamErrorFor(failed(418, 'teapot details'), CALL);

  assertEquals(error.status, 418);
  assertStringIncludes(error.message, 'teapot details');
});
