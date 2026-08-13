// The one call to Gemini, parameterised.
//
// There were two, and they had drifted in both directions:
//
//   * `generate-plan`'s copy had no 429 or 503 branch at all, so the commonest
//     condition on a free tier came back as a 500.
//   * `extract-intake`'s 404 message said "Set the GEMINI_MODEL secret" while the
//     function reads `EXTRACT_MODEL` — and that file's own doc comment insists at
//     length that it must *never* fall back to `GEMINI_MODEL`, because doing so
//     would hand extraction the contended model back. Following the instruction
//     the error gave you would have done nothing at all.
//
// The second is fixed structurally rather than by editing a string:
// `modelSecret` is a required parameter, so a caller cannot name a secret it does
// not read without saying so out loud. A copied error message can be wrong; a
// required argument has to be passed.

import { UpstreamError } from './http.ts';

export interface GeminiCall {
  /** The model id. Always from a secret — D8 makes the model a config choice. */
  model: string;
  /**
   * The name of the secret [model] came from, for the 404 message.
   *
   * Required, and that is the point. The two callers read **different** secrets
   * (`GEMINI_MODEL` and `EXTRACT_MODEL`), and the copy that hardcoded the wrong
   * one sent you to set a secret it never consults.
   */
  modelSecret: string;
  apiKey: string;
  prompt: string;
  /** `responseSchema`. What the model may return — see each caller. */
  schema: unknown;
  /**
   * 0.7 for composing plans, 0 for reading a sentence into typed fields.
   *
   * Explicit rather than defaulted: the two callers want genuinely different
   * values, and a default here would silently give one of them the other's.
   */
  temperature: number;
}

/**
 * Calls Gemini and returns its parsed JSON response.
 *
 * Throws [UpstreamError] for anything the API refused, carrying the status so a
 * caller — and now the app — can tell "wait" from "broken".
 */
export async function callGemini<T>(call: GeminiCall): Promise<T> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${call.model}:generateContent`;

  const response = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-goog-api-key': call.apiKey },
    body: JSON.stringify({
      contents: [{ role: 'user', parts: [{ text: call.prompt }] }],
      generationConfig: {
        responseMimeType: 'application/json',
        responseSchema: call.schema,
        temperature: call.temperature,
      },
    }),
  });

  if (!response.ok) {
    throw await upstreamErrorFor(response, call);
  }

  const data = await response.json();
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) {
    throw new UpstreamError(
      502,
      `Gemini returned no content: ${JSON.stringify(data).slice(0, 500)}`,
    );
  }

  return JSON.parse(text) as T;
}

/**
 * Maps a failed Gemini response onto an [UpstreamError].
 *
 * Exported so it can be tested against fabricated responses. This is the branch
 * that has already been wrong once in each direction, and testing it through
 * `callGemini` would mean either a live API call or mocking `fetch` globally.
 */
export async function upstreamErrorFor(
  response: Response,
  call: Pick<GeminiCall, 'model' | 'modelSecret'>,
): Promise<UpstreamError> {
  const body = await response.text();

  if (response.status === 404) {
    // Model names move faster than deploys. The fix is a secret, not an edit —
    // and it must name the secret THIS caller reads.
    return new UpstreamError(
      404,
      `Gemini rejected model "${call.model}" (404). Set the ${call.modelSecret} ` +
      `secret to a model available on your key. Body: ${body}`,
    );
  }

  if (response.status === 429) {
    return new UpstreamError(
      429,
      'Too many requests to the model just now. The free tier allows 5 per ' +
      'minute; try again shortly.',
    );
  }

  if (response.status === 503) {
    return new UpstreamError(
      503,
      'The model is busy right now. This is temporary — try again shortly.',
    );
  }

  return new UpstreamError(response.status, `Gemini ${response.status}: ${body}`);
}
