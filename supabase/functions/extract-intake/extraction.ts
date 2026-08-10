// Extraction — §7 step 0, on its own so it can be tested.
//
// Same reason `constraint_hash.ts` is a separate module: importing `index.ts`
// starts a server, which would make the part of this function most needing
// tests the hardest part to reach. Everything here is pure.
//
// INVARIANT 1 IS THE WHOLE POINT OF THIS FILE. Extraction reads a user's
// sentence and emits constraint VALUES ONLY — a budget, a time, a barangay, an
// occasion bucket. It must never emit a place or activity name. A user naming
// somewhere we have no row for ("take me to that café on the highway")
// resolves to a constraint or to a question, never to a suggestion. A
// conversational intake widens what the user may *say*; it widens nothing about
// what we may *claim*.
//
// That is enforced three ways, strongest first:
//
//   1. The response schema has nowhere to put a name. Four typed fields: an
//      integer, an ISO instant, one string, and an enum. This is not "we check
//      the output for place names" — it is "there is no field one could
//      occupy".
//   2. `origin_area` is the only string, and it must match a barangay we
//      already know. "Manila" fails and becomes an unfilled chip.
//   3. `validateExtraction` rejects anything that still got through, and is
//      exhaustively testable with fixtures. This is what holds when the model
//      misbehaves; the 20-utterance acceptance run proves it usually does not,
//      which is a weaker and separate claim.
//
// The prompt carries no candidate rows at all, so there is nothing to leak.

/** Coarse occasion buckets. Free text would poison the cache key (§9). */
export const OCCASIONS = ['casual', 'special'] as const;
export type Occasion = (typeof OCCASIONS)[number];

/**
 * The step-1 record, as much of it as language can supply.
 *
 * Four fields, matching what `constraintKey` already consumes, so extraction
 * introduces nothing new to the cache. Owned resources come from the user's
 * profile rather than from what they said; party size is fixed by D1.
 *
 * **Null is a real answer.** Anything unresolved is asked about, never guessed:
 * a default the user cannot see costs them their evening, an unfilled chip
 * costs them a tap.
 */
export interface IntakeConstraints {
  budget_php_cents: number | null;
  planned_for: string | null;
  origin_area: string | null;
  occasion: Occasion | null;
}

/**
 * What the model may return. Note what is absent: any field that could carry a
 * place name, an activity name, a price for something, or free text of any
 * kind.
 */
export const EXTRACTION_SCHEMA = {
  type: 'object',
  properties: {
    budget_php_cents: {
      type: 'integer',
      nullable: true,
      description: 'Whole-party budget in centavos. Null if not stated.',
    },
    planned_for: {
      type: 'string',
      nullable: true,
      description: 'ISO 8601 instant the outing starts. Null if not stated.',
    },
    origin_area: {
      type: 'string',
      nullable: true,
      description: 'Barangay the user is starting from. Null if not stated.',
    },
    occasion: {
      type: 'string',
      nullable: true,
      enum: [...OCCASIONS],
      description: 'Coarse bucket only.',
    },
  },
  required: ['budget_php_cents', 'planned_for', 'origin_area', 'occasion'],
} as const;

/**
 * The cache key's input.
 *
 * Lowercased, punctuation stripped, whitespace collapsed — so "Under ₱200,
 * tonight!" and "under 200 tonight" are one entry rather than two. This is what
 * makes a second phrasing free.
 *
 * Deliberately conservative: it does not stem, reorder or drop stop-words.
 * Merging two utterances that mean different things would serve the wrong
 * constraints confidently, which is far worse than paying for one more
 * extraction call.
 */
export function normaliseUtterance(text: string): string {
  return text
    .toLowerCase()
    // Currency symbols and punctuation carry no meaning once the number is
    // parsed out by the model. Keep digits and letters, including accented
    // ones — "café" must not become "caf".
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** SHA-256 of the normalised text, hex. The sentence itself is never stored. */
export async function utteranceHash(text: string): Promise<string> {
  const bytes = new TextEncoder().encode(normaliseUtterance(text));
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

export interface ValidationResult {
  constraints: IntakeConstraints;
  /** Fields the model returned that had to be dropped, for logging. */
  rejected: string[];
}

/**
 * Coerces raw model output into the record, dropping anything unsafe.
 *
 * **Rejection is never an error.** A dropped field becomes null, which becomes
 * an unfilled chip, which becomes a question — the same path as a value the
 * user simply did not mention. Failing the whole request because the model
 * offered a bad barangay would turn a recoverable misunderstanding into a dead
 * end.
 *
 * @param knownAreas barangays this app can cost a leg to. `origin_area` must be
 *   one of them: it is the only free string in the schema, and this is what
 *   stops "Manila" or a café's name becoming a stored constraint.
 */
export function validateExtraction(
  raw: unknown,
  knownAreas: readonly string[],
): ValidationResult {
  const rejected: string[] = [];
  const out: IntakeConstraints = {
    budget_php_cents: null,
    planned_for: null,
    origin_area: null,
    occasion: null,
  };

  if (typeof raw !== 'object' || raw === null) {
    return { constraints: out, rejected: ['not_an_object'] };
  }
  const input = raw as Record<string, unknown>;

  // Budget: must parse to a non-negative integer. ₱0 is a real budget (§9), so
  // zero is kept and only nonsense is dropped.
  const budget = input.budget_php_cents;
  if (typeof budget === 'number' && Number.isInteger(budget) && budget >= 0) {
    out.budget_php_cents = budget;
  } else if (budget !== null && budget !== undefined) {
    rejected.push('budget_php_cents');
  }

  // Time: must resolve to an instant. A string the model invented that does not
  // parse is a guess, and a guessed date silently plans the wrong evening.
  const when = input.planned_for;
  if (typeof when === 'string' && !Number.isNaN(Date.parse(when))) {
    out.planned_for = new Date(when).toISOString();
  } else if (when !== null && when !== undefined) {
    rejected.push('planned_for');
  }

  // Origin: must be a barangay we know. Case-insensitive because the model will
  // capitalise inconsistently, but the STORED value is our spelling, not the
  // model's — `fare_for` matches barangay by exact string, so accepting the
  // model's casing would make every leg to that stop unpriced.
  const area = input.origin_area;
  if (typeof area === 'string' && area.trim() !== '') {
    const match = knownAreas.find(
      (known) => known.toLowerCase() === area.trim().toLowerCase(),
    );
    if (match) {
      out.origin_area = match;
    } else {
      // This is the branch that catches "Starbucks", "the café on the highway",
      // "Manila" and "Cebu" alike. They are not distinguished, and do not need
      // to be: anything that is not a barangay we can cost a leg to is not a
      // constraint we can use.
      rejected.push('origin_area');
    }
  } else if (area !== null && area !== undefined) {
    rejected.push('origin_area');
  }

  // Occasion: enum or nothing. Free text here would reach the cache key and
  // fragment it into single-use entries (§9).
  const occasion = input.occasion;
  if (typeof occasion === 'string' && (OCCASIONS as readonly string[]).includes(occasion)) {
    out.occasion = occasion as Occasion;
  } else if (occasion !== null && occasion !== undefined) {
    rejected.push('occasion');
  }

  return { constraints: out, rejected };
}

/**
 * The prompt. It contains no candidate rows, by design (§7 step 0).
 *
 * `knownAreas` is the one piece of database content here, and it is a closed
 * list of barangay names rather than places — it tells the model what values
 * are legal, not what exists to suggest. Sending it is what lets "we're in
 * Turo" resolve at all.
 */
export function buildExtractionPrompt(
  utterance: string,
  knownAreas: readonly string[],
  nowIso: string,
): string {
  return [
    'You convert one message from a couple planning a date in Bocaue, Bulacan',
    'into structured constraints. You do not suggest anything.',
    '',
    `The current time is ${nowIso} (UTC). The user is in the Philippines`,
    '(UTC+8), so "tonight" and "this weekend" are relative to their local time.',
    '',
    'Rules:',
    '- Return ONLY the four fields in the schema.',
    '- Use null for anything the message does not state. Do not guess.',
    '- Budget is for the whole party, in centavos: "₱200" is 20000.',
    '- origin_area must be exactly one of these barangays, or null:',
    `  ${knownAreas.join(', ')}`,
    '- Never return a business, landmark, shop or activity name in any field.',
    '  If the user names a place, that is not a constraint — return null for',
    '  origin_area unless they named one of the barangays above.',
    '- occasion is "special" for anniversaries, birthdays and proposals;',
    '  "casual" otherwise; null if unclear.',
    '',
    `Message: ${utterance}`,
  ].join('\n');
}
