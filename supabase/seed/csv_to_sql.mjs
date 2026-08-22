#!/usr/bin/env node
//
// Turns the seed CSVs in this directory into idempotent SQL.
//
//   node supabase/seed/csv_to_sql.mjs            # print SQL to stdout
//   node supabase/seed/csv_to_sql.mjs --out x.sql
//
// The CSVs are the source of truth for Amora's curated data; their git history
// is the data's history (docs/00-architecture.md §6). This script only converts
// them — it never invents rows.
//
// What it does for you, so the CSVs stay human-editable:
//   * pesos -> centavos          180 / 180.50  ->  18000 / 18050
//   * opening hours -> jsonb     "mon-fri 10:00-22:00; sat 08:00-23:00"
//   * resource slugs -> uuid[]   resolved against resource_catalog at insert
//
// Every statement is an upsert keyed on a natural key, so re-running after you
// edit a row updates that row instead of inserting a duplicate.
//
// Rows whose key starts with EXAMPLE- are template rows and are always skipped,
// so an untouched template can never seed fake data into the database.
//
// No npm dependencies, by design — this must keep working with nothing but a
// Node install.

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SEED_DIR = dirname(fileURLToPath(import.meta.url));
// Matches both `EXAMPLE-fake-cafe` (slug keys) and `EXAMPLE Fake Barangay A`
// (free-text keys like transit_fares.from_area).
const EXAMPLE_PREFIX = 'EXAMPLE';
const DAYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

/**
 * The exact columns each CSV must have, and the natural key that must be unique
 * within it.
 *
 * These are checked before any SQL is produced. A seeding tool that quietly
 * drops a column is worse than no tool: a header typo once cost every activity
 * its resource links with no error at all, and unquoted commas silently shifted
 * one field's value into the next column.
 */
const CSV_SPECS = {
  'resource_catalog.csv': {
    columns: ['slug', 'name', 'category', 'icon'],
    key: ['slug'],
  },
  'places.csv': {
    columns: [
      'slug', 'name', 'category', 'lat', 'lng', 'address', 'barangay', 'city',
      'opening_hours', 'price_min_php', 'price_max_php', 'indoor',
      'sunset_facing', 'social_url', 'contact_number', 'notes', 'verified_on',
      'verified_method',
    ],
    key: ['slug'],
  },
  'activities.csv': {
    columns: [
      'slug', 'title', 'category', 'min_budget_php', 'max_budget_php',
      'duration_minutes', 'required_resource_slugs', 'weather_dependent',
      'is_diy', 'tutorial_url', 'cost_kind', 'budget_is_per_person',
    ],
    key: ['slug'],
  },
  'transit_fares.csv': {
    columns: [
      'from_area', 'to_area', 'mode', 'fare_php', 'is_per_person', 'verified_at',
    ],
    key: ['from_area', 'to_area', 'mode'],
  },
  'place_notes.csv': {
    columns: ['place_slug', 'source_label', 'body', 'added_at'],
    key: ['place_slug', 'source_label'],
  },
};

// --- CSV -------------------------------------------------------------------

/** Minimal RFC 4180 parser. Handles quoted fields containing commas/newlines. */
function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = '';
  let inQuotes = false;
  let i = 0;

  text = text.replace(/^﻿/, ''); // strip BOM

  while (i < text.length) {
    const c = text[i];

    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i += 2;
          continue;
        }
        inQuotes = false;
        i += 1;
        continue;
      }
      field += c;
      i += 1;
      continue;
    }

    if (c === '"') {
      inQuotes = true;
      i += 1;
    } else if (c === ',') {
      row.push(field);
      field = '';
      i += 1;
    } else if (c === '\n') {
      row.push(field);
      rows.push(row);
      row = [];
      field = '';
      i += 1;
    } else if (c === '\r') {
      i += 1;
    } else {
      field += c;
      i += 1;
    }
  }

  if (field !== '' || row.length > 0) {
    row.push(field);
    rows.push(row);
  }

  return rows;
}

/**
 * Reads a CSV into objects keyed by header, validating it first.
 *
 * Refuses to return anything if the header is wrong, a row has the wrong number
 * of fields, or the natural key repeats — each of which would otherwise corrupt
 * data silently rather than fail.
 */
function readCsv(name) {
  const spec = CSV_SPECS[name];
  if (!spec) throw new Error(`No column spec defined for ${name}`);

  const path = join(SEED_DIR, name);
  if (!existsSync(path)) throw new Error(`Missing seed file: ${name}`);

  const rows = parseCsv(readFileSync(path, 'utf8'));
  if (rows.length === 0) {
    throw new Error(`${name} is empty — it needs at least a header row.`);
  }

  const headers = rows[0].map((h) => h.trim());
  assertHeaders(name, headers, spec.columns);

  const records = [];
  for (let i = 1; i < rows.length; i += 1) {
    const row = rows[i];
    const line = i + 1; // 1-based, counting the header

    if (row.every((v) => v.trim() === '')) continue;

    if (row.length !== headers.length) {
      throw new Error(
        `${name}:${line} — expected ${headers.length} columns but found ${row.length}. ` +
          'A field containing a comma must be wrapped in double quotes, ' +
          'e.g. "quiet on weekdays, busy after 5pm".',
      );
    }

    const record = { __line: line, __file: name };
    headers.forEach((h, j) => {
      record[h] = row[j].trim();
    });
    records.push(record);
  }

  assertUniqueKey(name, records, spec.key);
  return records;
}

/** The header must match the spec exactly — no missing and no extra columns. */
function assertHeaders(name, headers, expected) {
  const missing = expected.filter((c) => !headers.includes(c));
  const unknown = headers.filter((c) => !expected.includes(c));
  if (missing.length === 0 && unknown.length === 0) return;

  const problems = [];
  if (missing.length > 0) problems.push(`missing column(s): ${missing.join(', ')}`);
  if (unknown.length > 0) problems.push(`unrecognised column(s): ${unknown.join(', ')}`);

  throw new Error(
    `${name} header is wrong — ${problems.join('; ')}.\n` +
      `  expected exactly: ${expected.join(', ')}\n` +
      `  found:            ${headers.join(', ')}`,
  );
}

/**
 * The natural key is what the upsert conflicts on, so a repeat inside one CSV
 * means the later row silently overwrites the earlier one on import.
 */
function assertUniqueKey(name, records, keyFields) {
  const seen = new Map();

  for (const record of records) {
    const values = keyFields.map((f) => record[f]);
    // JSON rather than joining on a separator, so that ["a b", "c"] and
    // ["a", "b c"] stay distinct keys. This used to join on a NUL byte, which
    // was collision-safe for the same reason but made git treat this whole file
    // as binary — and an unreviewable diff on the tool that guards the seed data
    // is a worse problem than the one it solved.
    const key = JSON.stringify(values);

    if (seen.has(key)) {
      throw new Error(
        `${name}:${record.__line} — duplicate ${keyFields.join(' + ')} ` +
          `"${values.join(', ')}", already used on line ${seen.get(key)}. ` +
          'These upsert onto the same row, so one would silently overwrite the other. ' +
          'Give each row its own key.',
      );
    }
    seen.set(key, record.__line);
  }
}

// --- SQL literals ----------------------------------------------------------

const sqlText = (v) =>
  v === undefined || v === null || v === '' ? 'null' : `'${v.replace(/'/g, "''")}'`;

// Strict, because a boolean that quietly defaults is a boolean that decides
// money. `budget_is_per_person` multiplies a materials budget by party size,
// so `flase` used to mean "one set of ingredients" and cost the couple half
// what it should have — with nothing anywhere saying so. Every boolean column
// in every seed CSV is already exactly `true` or `false`; this keeps it that
// way rather than coercing the next typo.
function sqlBool(v, { field, row } = { field: 'boolean', row: {} }) {
  const s = String(v).toLowerCase();
  if (s !== 'true' && s !== 'false') {
    throw new Error(
      `${row.__file}:${row.__line} — ${field} must be true or false: "${v}"`);
  }
  return s;
}

function sqlNumber(v, { field, row }) {
  if (v === '') return 'null';
  if (!/^-?\d+(\.\d+)?$/.test(v)) {
    throw new Error(`${row.__file}:${row.__line} — ${field} is not a number: "${v}"`);
  }
  return v;
}

function sqlInt(v, { field, row }) {
  if (v === '') return 'null';
  if (!/^-?\d+$/.test(v)) {
    throw new Error(`${row.__file}:${row.__line} — ${field} must be a whole number: "${v}"`);
  }
  return v;
}

function sqlTimestamp(v) {
  return v === '' ? 'null' : `${sqlText(v)}::timestamptz`;
}

const sqlTextArray = (values) =>
  `array[${values.map((v) => sqlText(v)).join(', ')}]::text[]`;

/**
 * Pesos -> integer centavos, without floating point.
 * CLAUDE.md: money is integer centavos, never a float.
 */
function pesosToCents(v, { field, row }) {
  if (v === '') return 'null';

  const match = /^(\d+)(?:\.(\d{1,2}))?$/.exec(v);
  if (!match) {
    throw new Error(
      `${row.__file}:${row.__line} — ${field} must be pesos like 180 or 180.50, got "${v}"`,
    );
  }

  const [, whole, fraction = ''] = match;
  return String(Number(whole) * 100 + Number(fraction.padEnd(2, '0')));
}

/**
 * "mon-fri 10:00-22:00; sat-sun 08:00-23:00" -> jsonb keyed by day.
 *
 * Days may be a single day (`sat`), a range (`mon-fri`), or a list
 * (`mon,wed,fri`). Times are `HH:MM-HH:MM`, or `24h` for all day. Days that are
 * never mentioned are closed, so omit them.
 *
 * A closing time earlier than its opening time wraps past midnight:
 * `fri 20:00-02:00` is Friday evening into Saturday morning. The day recorded is
 * the day the place *opens*, which is how a reader would say it out loud. Amora
 * plans evenings, so places that shut at 1am are the interesting rows, not an
 * edge case — `public.is_open_at` reads the wrap back out.
 */
function openingHoursToJsonb(spec, row) {
  if (spec === '') return 'null';

  const hours = {};

  for (const rawSegment of spec.split(';')) {
    const segment = rawSegment.trim();
    if (segment === '') continue;

    const match = /^([a-z,\-]+)\s+(.+)$/i.exec(segment);
    if (!match) {
      throw new Error(
        `${row.__file}:${row.__line} — cannot read opening hours segment "${segment}". ` +
          'Expected something like "mon-fri 10:00-22:00".',
      );
    }

    const [, daySpec, timeSpec] = match;
    const range = parseTimeRange(timeSpec.trim(), segment, row);
    for (const day of expandDays(daySpec.toLowerCase(), segment, row)) {
      (hours[day] ??= []).push(range);
    }
  }

  return `${sqlText(JSON.stringify(hours))}::jsonb`;
}

function parseTimeRange(timeSpec, segment, row) {
  if (timeSpec.toLowerCase() === '24h') return ['00:00', '24:00'];

  const match = /^(\d{2}:\d{2})-(\d{2}:\d{2})$/.exec(timeSpec);
  if (!match) {
    throw new Error(
      `${row.__file}:${row.__line} — cannot read times "${timeSpec}" in "${segment}". ` +
        'Expected HH:MM-HH:MM or 24h.',
    );
  }

  const [, opens, closes] = match;

  // Equal times are genuinely ambiguous — "10:00-10:00" could mean closed all day
  // or open all day, and guessing either way silently misrepresents a real place.
  if (opens === closes) {
    throw new Error(
      `${row.__file}:${row.__line} — opening and closing time are both "${opens}" ` +
        `in "${segment}". Write "24h" for all day, or omit the day if it is closed.`,
    );
  }

  return [opens, closes];
}

function expandDays(daySpec, segment, row) {
  const result = [];

  for (const part of daySpec.split(',')) {
    if (part.includes('-')) {
      const [from, to] = part.split('-');
      const start = DAYS.indexOf(from);
      const end = DAYS.indexOf(to);
      if (start === -1 || end === -1) {
        throw new Error(
          `${row.__file}:${row.__line} — unknown day range "${part}" in "${segment}".`,
        );
      }
      // Wraps across the end of the week, e.g. fri-mon.
      for (let i = start; ; i = (i + 1) % DAYS.length) {
        result.push(DAYS[i]);
        if (i === end) break;
      }
    } else {
      if (!DAYS.includes(part)) {
        throw new Error(
          `${row.__file}:${row.__line} — unknown day "${part}" in "${segment}".`,
        );
      }
      result.push(part);
    }
  }

  return [...new Set(result)];
}

// --- Statement builders ----------------------------------------------------

/** Drops template rows so an untouched CSV can never seed fake data. */
function withoutExamples(rows, keyField, label, skipped) {
  return rows.filter((row) => {
    const isExample = (row[keyField] ?? '').startsWith(EXAMPLE_PREFIX);
    if (isExample) skipped.push(`${label} (${row[keyField]})`);
    return !isExample;
  });
}

function resourceCatalogSql(rows) {
  return rows.map(
    (r) => `insert into public.resource_catalog (slug, name, category, icon)
values (${sqlText(r.slug)}, ${sqlText(r.name)}, ${sqlText(r.category)}, ${sqlText(r.icon)})
on conflict (slug) do update set
  name = excluded.name,
  category = excluded.category,
  icon = excluded.icon;`,
  );
}

const VERIFIED_METHODS = ['visited', 'phoned', 'resident', 'generated'];

// Demo rows are generated, carry no verification of any kind, and are removed with
// `delete from public.places where verified_method = 'generated'`. That command is
// only as trustworthy as the pairing below, so the pairing is checked rather than
// remembered: a generated row must carry a demo- slug, and a demo- slug must
// declare itself generated. See supabase/seed/DEMO-DATA.md.
const DEMO_SLUG_PREFIX = 'demo-';

/**
 * §10.4a, made mechanical.
 *
 * Two rules, both of which would otherwise be a habit someone remembers or
 * doesn't. A typo ('phone', 'visit') would fail at the database as a constraint
 * violation with no idea which row caused it; catching it here names the file and
 * the slug. And a priced row marked `resident` is the one thing §10.4a forbids
 * outright — a price recalled from memory is a guess with a local accent, and the
 * whole desk-verification argument collapses the moment one gets in.
 *
 * Blank is allowed: the column is new, and a row that has not said how it was
 * established is honest about that. It is the *combination* of a price and a
 * claim of resident knowledge that is never allowed.
 */
function assertVerifiedMethods(rows) {
  for (const r of rows) {
    const method = (r.verified_method ?? '').trim();
    const where = `${r.__file}:${r.__line}`;

    if (method !== '' && !VERIFIED_METHODS.includes(method)) {
      throw new Error(
        `${where} — verified_method is "${method}" on '${r.slug}'. ` +
          `Expected one of: ${VERIFIED_METHODS.join(', ')}.`,
      );
    }

    const price = Number.parseFloat(r.price_min_php || '0') || 0;
    if (method === 'resident' && price > 0) {
      throw new Error(
        `${where} — '${r.slug}' claims verified_method "resident" with a price ` +
          `of ₱${price}.\n` +
          '  A price may only come from a visit or a phone call ' +
          '(docs/00-architecture.md §10.4a).\n' +
          '  Resident knowledge covers facts that do not move, and a price is ' +
          'not one of them.\n' +
          '  Either phone the place and record what they say, or drop the price ' +
          'to 0 if it is genuinely free.',
      );
    }

    // The demo wipe is `delete ... where verified_method = 'generated'`. Both
    // halves of this pairing keep that command exact: a generated row that lost
    // its prefix would be invisible to a slug-based sweep, and a demo- row that
    // lost its method would survive the wipe and sit in the catalogue looking
    // curated. Neither is recoverable by reading the table afterwards.
    const isDemoSlug = r.slug.startsWith(DEMO_SLUG_PREFIX);

    if (method === 'generated' && !isDemoSlug) {
      throw new Error(
        `${where} — '${r.slug}' is verified_method "generated" but its slug does ` +
          `not start with "${DEMO_SLUG_PREFIX}".
` +
          '  Generated rows are demo data and must be removable by slug as well ' +
          'as by method (supabase/seed/DEMO-DATA.md).',
      );
    }

    if (isDemoSlug && method !== 'generated') {
      throw new Error(
        `${where} — '${r.slug}' carries the "${DEMO_SLUG_PREFIX}" prefix but its ` +
          `verified_method is "${method || '(blank)'}".
` +
          '  A demo slug must declare itself generated, or the wipe leaves it ' +
          'behind looking like curated data.',
      );
    }
  }
}

function placesSql(rows) {
  return rows.map((r) => {
    const ctx = (field) => ({ field, row: r });
    return `insert into public.places (
  slug, name, category, lat, lng, address, barangay, city, opening_hours,
  price_min_php_cents, price_max_php_cents, indoor, sunset_facing,
  verification_tier, source, social_url, contact_number, notes,
  verified_at, verified_on, verified_method
) values (
  ${sqlText(r.slug)}, ${sqlText(r.name)}, ${sqlText(r.category)},
  ${sqlNumber(r.lat, ctx('lat'))}, ${sqlNumber(r.lng, ctx('lng'))},
  ${sqlText(r.address)}, ${sqlText(r.barangay)}, ${sqlText(r.city)},
  ${openingHoursToJsonb(r.opening_hours, r)},
  ${pesosToCents(r.price_min_php, ctx('price_min_php'))},
  ${pesosToCents(r.price_max_php, ctx('price_max_php'))},
  ${sqlBool(r.indoor, ctx('indoor'))}, ${sqlBool(r.sunset_facing, ctx('sunset_facing'))},
  'curated', 'owner',
  ${sqlText(r.social_url)}, ${sqlText(r.contact_number)}, ${sqlText(r.notes)},
  now(), ${r.verified_on === '' ? 'null' : `${sqlText(r.verified_on)}::date`},
  ${sqlText(r.verified_method)}
)
on conflict (slug) do update set
  name = excluded.name,
  category = excluded.category,
  lat = excluded.lat,
  lng = excluded.lng,
  address = excluded.address,
  barangay = excluded.barangay,
  city = excluded.city,
  opening_hours = excluded.opening_hours,
  price_min_php_cents = excluded.price_min_php_cents,
  price_max_php_cents = excluded.price_max_php_cents,
  indoor = excluded.indoor,
  sunset_facing = excluded.sunset_facing,
  social_url = excluded.social_url,
  contact_number = excluded.contact_number,
  notes = excluded.notes,
  verified_on = excluded.verified_on,
  verified_method = excluded.verified_method;`;
  });
}

function activitiesSql(rows) {
  const statements = [];

  // Fail loudly on a resource slug that does not exist, rather than quietly
  // seeding an activity with an empty requirement list.
  const referenced = [
    ...new Set(
      rows.flatMap((r) =>
        (r.required_resource_slugs ?? '').split('|').map((s) => s.trim()).filter(Boolean),
      ),
    ),
  ];

  if (referenced.length > 0) {
    statements.push(`do $$
declare missing text;
begin
  select string_agg(s, ', ') into missing
  from unnest(${sqlTextArray(referenced)}) as s
  where not exists (select 1 from public.resource_catalog rc where rc.slug = s);
  if missing is not null then
    raise exception 'Unknown resource slug(s) in activities.csv: %', missing;
  end if;
end $$;`);
  }

  for (const r of rows) {
    const ctx = (field) => ({ field, row: r });
    const slugs = (r.required_resource_slugs ?? '')
      .split('|')
      .map((s) => s.trim())
      .filter(Boolean);

    const resourceIds =
      slugs.length === 0
        ? `'{}'::uuid[]`
        : `array(select rc.id from public.resource_catalog rc where rc.slug = any(${sqlTextArray(slugs)}))`;

    // cost_kind decides whether this budget is added to a plan total at all,
    // so an unrecognised value must stop the import rather than reach the check
    // constraint as an opaque failure halfway through applying seed.sql.
    if (r.cost_kind !== 'materials' && r.cost_kind !== 'venue') {
      throw new Error(
        `${r.__file}:${r.__line} — cost_kind must be materials or venue: ` +
          `"${r.cost_kind}". materials is bought beforehand and adds to the ` +
          'plan total; venue is spent at the paired place, which already ' +
          'carries it as the place price.',
      );
    }

    statements.push(`insert into public.activities (
  slug, title, category, min_budget_php_cents, max_budget_php_cents,
  duration_minutes, required_resource_ids, weather_dependent, is_diy,
  tutorial_url, cost_kind, budget_is_per_person
) values (
  ${sqlText(r.slug)}, ${sqlText(r.title)}, ${sqlText(r.category)},
  ${pesosToCents(r.min_budget_php, ctx('min_budget_php'))},
  ${pesosToCents(r.max_budget_php, ctx('max_budget_php'))},
  ${sqlInt(r.duration_minutes, ctx('duration_minutes'))},
  ${resourceIds},
  ${sqlBool(r.weather_dependent, ctx('weather_dependent'))},
  ${sqlBool(r.is_diy, ctx('is_diy'))},
  ${sqlText(r.tutorial_url)},
  ${sqlText(r.cost_kind)},
  ${sqlBool(r.budget_is_per_person, ctx('budget_is_per_person'))}
)
on conflict (slug) do update set
  title = excluded.title,
  category = excluded.category,
  min_budget_php_cents = excluded.min_budget_php_cents,
  max_budget_php_cents = excluded.max_budget_php_cents,
  duration_minutes = excluded.duration_minutes,
  required_resource_ids = excluded.required_resource_ids,
  weather_dependent = excluded.weather_dependent,
  is_diy = excluded.is_diy,
  tutorial_url = excluded.tutorial_url,
  cost_kind = excluded.cost_kind,
  budget_is_per_person = excluded.budget_is_per_person;`);
  }

  return statements;
}

function transitFaresSql(rows) {
  return rows.map((r) => {
    const ctx = (field) => ({ field, row: r });
    return `insert into public.transit_fares (
  from_area, to_area, mode, fare_php_cents, is_per_person, verified_at
) values (
  ${sqlText(r.from_area)}, ${sqlText(r.to_area)}, ${sqlText(r.mode)},
  ${pesosToCents(r.fare_php, ctx('fare_php'))},
  ${sqlBool(r.is_per_person, ctx('is_per_person'))}, ${sqlTimestamp(r.verified_at)}
)
on conflict (from_area, to_area, mode) do update set
  fare_php_cents = excluded.fare_php_cents,
  is_per_person = excluded.is_per_person,
  verified_at = excluded.verified_at;`;
  });
}

function placeNotesSql(rows) {
  const statements = [];

  const referenced = [...new Set(rows.map((r) => r.place_slug).filter(Boolean))];
  if (referenced.length > 0) {
    statements.push(`do $$
declare missing text;
begin
  select string_agg(s, ', ') into missing
  from unnest(${sqlTextArray(referenced)}) as s
  where not exists (select 1 from public.places p where p.slug = s);
  if missing is not null then
    raise exception 'Unknown place slug(s) in place_notes.csv: %', missing;
  end if;
end $$;`);
  }

  for (const r of rows) {
    statements.push(`insert into public.place_notes (place_id, source_label, body, added_at)
select p.id, ${sqlText(r.source_label)}, ${sqlText(r.body)},
       coalesce(${sqlTimestamp(r.added_at)}, now())
from public.places p
where p.slug = ${sqlText(r.place_slug)}
on conflict (place_id, source_label) do update set
  body = excluded.body,
  added_at = excluded.added_at;`);
  }

  return statements;
}

// --- Main ------------------------------------------------------------------

function main() {
  const skipped = [];

  // Order matters: activities resolve resource slugs, notes resolve place slugs.
  const resources = withoutExamples(
    readCsv('resource_catalog.csv'), 'slug', 'resource_catalog', skipped);
  const places = withoutExamples(readCsv('places.csv'), 'slug', 'places', skipped);
  const activities = withoutExamples(
    readCsv('activities.csv'), 'slug', 'activities', skipped);
  const fares = withoutExamples(
    readCsv('transit_fares.csv'), 'from_area', 'transit_fares', skipped);
  const notes = withoutExamples(
    readCsv('place_notes.csv'), 'place_slug', 'place_notes', skipped);

  // Validate before emitting a single statement, like every other check here:
  // a refusal costs nothing, a half-applied seed costs a manual cleanup.
  assertVerifiedMethods(places);

  const sections = [
    ['resource_catalog', resourceCatalogSql(resources)],
    ['places', placesSql(places)],
    ['activities', activitiesSql(activities)],
    ['transit_fares', transitFaresSql(fares)],
    ['place_notes', placeNotesSql(notes)],
  ];

  const out = ['-- Generated by supabase/seed/csv_to_sql.mjs. Do not edit by hand.'];
  for (const [name, statements] of sections) {
    out.push(`\n-- ${name}: ${statements.length} statement(s)`);
    out.push(...statements);
  }

  const sql = `${out.join('\n')}\n`;
  const outIndex = process.argv.indexOf('--out');
  if (outIndex !== -1 && process.argv[outIndex + 1]) {
    writeFileSync(process.argv[outIndex + 1], sql);
  } else {
    process.stdout.write(sql);
  }

  // Progress goes to stderr so it never contaminates piped SQL.
  const counts =
    `resource_catalog ${resources.length}, places ${places.length}, ` +
    `activities ${activities.length}, transit_fares ${fares.length}, ` +
    `place_notes ${notes.length}`;
  process.stderr.write(`Seed rows: ${counts}\n`);

  if (skipped.length > 0) {
    process.stderr.write(
      `\nSkipped ${skipped.length} EXAMPLE- template row(s):\n` +
        skipped.map((s) => `  - ${s}`).join('\n') +
        '\nReplace them with real verified rows before seeding.\n',
    );
  }
}

try {
  main();
} catch (error) {
  process.stderr.write(`Seed import failed: ${error.message}\n`);
  process.exit(1);
}
