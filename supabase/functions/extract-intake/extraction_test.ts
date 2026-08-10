// Tests for extraction — the guard, not the model.
//
//   npx deno test supabase/functions/extract-intake/
//
// These prove the system is safe **even if the model misbehaves**. The
// acceptance run (`acceptance.mjs`) proves the model usually does not, which is
// a weaker and separate claim: it samples 20 utterances against one model
// version, and D8 makes the model a config choice that can change under us.
// This file is the part that still holds the day someone sets GEMINI_MODEL to
// something new.
//
// Every case here is a *hostile* model output — not a hostile user. The user
// can say anything they like; what matters is that nothing they say can put a
// place name into a stored constraint.

import { assertEquals, assertNotEquals } from 'jsr:@std/assert@1';
import {
  normaliseUtterance,
  utteranceHash,
  validateExtraction,
} from './extraction.ts';

const AREAS = ['Bunlo', 'Duhat', 'Lolomboy', 'Poblacion', 'Turo', 'Wakas'];

const CLEAN = {
  budget_php_cents: 20000,
  planned_for: '2026-08-08T10:00:00.000Z',
  origin_area: 'Poblacion',
  occasion: 'casual',
};

Deno.test('a well-formed extraction passes through unchanged', () => {
  const { constraints, rejected } = validateExtraction(CLEAN, AREAS);

  assertEquals(rejected, []);
  assertEquals(constraints.budget_php_cents, 20000);
  assertEquals(constraints.origin_area, 'Poblacion');
  assertEquals(constraints.occasion, 'casual');
});

// --- invariant 1: no place may become a constraint -------------------------
//
// origin_area is the only free string in the schema, so it is the only way a
// name could ever reach storage. Each of these is a real thing a model might
// return when a user names somewhere.

Deno.test('a business name in origin_area is rejected, not stored', () => {
  for (const name of [
    'Starbucks',
    'Jollibee Bocaue',
    'the café on the highway',
    'Aling Nena\'s Carinderia',
  ]) {
    const { constraints, rejected } = validateExtraction(
      { ...CLEAN, origin_area: name },
      AREAS,
    );
    assertEquals(constraints.origin_area, null, name);
    assertEquals(rejected.includes('origin_area'), true, name);
  }
});

Deno.test('a real place that is not a barangay we cover is rejected', () => {
  // D1 scopes this to Bocaue. "Manila" and "Cebu" are not attacks — they are
  // what an out-of-town user genuinely types — and the answer is the same:
  // not a constraint we can use, so a question rather than a guess.
  for (const place of ['Manila', 'Cebu', 'Quezon City', 'Bulacan']) {
    const { constraints } = validateExtraction(
      { ...CLEAN, origin_area: place },
      AREAS,
    );
    assertEquals(constraints.origin_area, null, place);
  }
});

Deno.test('the stored barangay is our spelling, never the model\'s', () => {
  // fare_for matches barangay by exact string. Accepting "poblacion" as typed
  // would make every leg to that stop unpriced forever, with nothing on screen
  // explaining why — a silent failure, which is the worst kind here.
  const { constraints } = validateExtraction(
    { ...CLEAN, origin_area: 'POBLACION' },
    AREAS,
  );
  assertEquals(constraints.origin_area, 'Poblacion');
});

Deno.test('extra fields the model invents are ignored entirely', () => {
  // A model that decides to be helpful and add a suggestion must not have it
  // survive. Nothing outside the four fields is read at all.
  const { constraints } = validateExtraction(
    {
      ...CLEAN,
      place_name: 'Riverside Park',
      suggestion: 'Try the milk tea place',
      activity: 'picnic',
    },
    AREAS,
  );
  assertEquals(Object.keys(constraints).sort(), [
    'budget_php_cents',
    'occasion',
    'origin_area',
    'planned_for',
  ]);
});

// --- the other three fields ------------------------------------------------

Deno.test('a budget must be a non-negative integer, and zero is real', () => {
  // ₱0 is a first-class budget (§9), so zero must survive while nonsense does
  // not. Treating 0 as "unset" would quietly delete the free-plan path.
  assertEquals(
    validateExtraction({ ...CLEAN, budget_php_cents: 0 }, AREAS)
      .constraints.budget_php_cents,
    0,
  );

  for (const bad of [-500, 12.5, '200', 'two hundred', {}]) {
    const { constraints, rejected } = validateExtraction(
      { ...CLEAN, budget_php_cents: bad },
      AREAS,
    );
    assertEquals(constraints.budget_php_cents, null, JSON.stringify(bad));
    assertEquals(rejected.includes('budget_php_cents'), true, JSON.stringify(bad));
  }
});

Deno.test('a time that does not parse is dropped rather than guessed', () => {
  // A guessed date plans the wrong evening and looks entirely correct doing it.
  for (const bad of ['tonight', 'soon', 'next Caturday', '']) {
    const { constraints } = validateExtraction(
      { ...CLEAN, planned_for: bad },
      AREAS,
    );
    assertEquals(constraints.planned_for, null, bad);
  }
});

Deno.test('occasion is a closed bucket, never free text', () => {
  // Free text here would reach the cache key and fragment it into single-use
  // entries — the objection §9 answers structurally.
  assertEquals(
    validateExtraction({ ...CLEAN, occasion: 'special' }, AREAS)
      .constraints.occasion,
    'special',
  );
  assertEquals(
    validateExtraction(
      { ...CLEAN, occasion: 'our third anniversary, she has been stressed' },
      AREAS,
    ).constraints.occasion,
    null,
  );
});

Deno.test('null everywhere is a valid answer, not a failure', () => {
  // "Plan something nice" states no constraints at all. Every field null means
  // four questions, which is the honest response — not an error, and not a set
  // of defaults the user cannot see.
  const { constraints, rejected } = validateExtraction(
    {
      budget_php_cents: null,
      planned_for: null,
      origin_area: null,
      occasion: null,
    },
    AREAS,
  );
  assertEquals(rejected, []);
  assertEquals(constraints.budget_php_cents, null);
  assertEquals(constraints.origin_area, null);
});

Deno.test('garbage instead of an object yields an empty record', () => {
  for (const bad of [null, 'a string', 42, []]) {
    const { constraints } = validateExtraction(bad, AREAS);
    assertEquals(constraints.origin_area, null);
    assertEquals(constraints.budget_php_cents, null);
  }
});

// --- normalisation, in both directions -------------------------------------
//
// Same discipline as constraint_hash_test.ts: a normaliser can fail by merging
// utterances that mean different things (wrong constraints, served confidently)
// or by separating ones that mean the same (no cache, which the free tier
// cannot afford). A suite that only checks one direction passes trivially — the
// identity function passes the separation half, and `() => ''` passes the
// merging half.

Deno.test('phrasings that mean the same thing share one entry', async () => {
  const pairs: [string, string][] = [
    ['Under ₱200, tonight!', 'under 200 tonight'],
    ['  Tonight   under  200  ', 'Tonight under 200'],
    ['Anniversary dinner.', 'anniversary dinner'],
  ];

  for (const [a, b] of pairs) {
    assertEquals(normaliseUtterance(a), normaliseUtterance(b), `${a} vs ${b}`);
    assertEquals(await utteranceHash(a), await utteranceHash(b), `${a} vs ${b}`);
  }
});

Deno.test('utterances that mean different things stay apart', async () => {
  const pairs: [string, string][] = [
    ['under 200 tonight', 'under 500 tonight'],
    ['tonight in Turo', 'tonight in Bunlo'],
    ['under 200 tonight', 'under 200 tomorrow'],
    // Word order changes meaning often enough that reordering would be unsafe,
    // so normalisation deliberately does not do it.
    ['from Turo to Bunlo', 'from Bunlo to Turo'],
  ];

  for (const [a, b] of pairs) {
    assertNotEquals(normaliseUtterance(a), normaliseUtterance(b), `${a} vs ${b}`);
    assertNotEquals(await utteranceHash(a), await utteranceHash(b), `${a} vs ${b}`);
  }
});

Deno.test('accented letters survive normalisation', () => {
  // Stripping non-ASCII would turn "café" into "caf" and, worse, could collapse
  // two different words. Tagalog and Spanish loanwords are ordinary here.
  assertEquals(normaliseUtterance('Café tonight'), 'café tonight');
  assertNotEquals(normaliseUtterance('café'), normaliseUtterance('cafe'));
});

Deno.test('the hash is of the normalised text, and the text is not recoverable', async () => {
  const hash = await utteranceHash('Under ₱200 tonight');
  assertEquals(hash.length, 64);
  assertEquals(/^[0-9a-f]+$/.test(hash), true);
  assertEquals(hash.includes('200'), false);
});
