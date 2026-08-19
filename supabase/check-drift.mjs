#!/usr/bin/env node
// Does the repository match the project? Run it; do not remember it.
//
//   node supabase/check-drift.mjs
//
// Exit codes, and the distinction is the point:
//
//   0  everything checked, everything agrees
//   1  DRIFT — the repo and the project disagree
//   2  COULD NOT CHECK — something was unverifiable, which is not a pass
//
// **There is no silent success.** A check that reports "fine" when it did not
// actually look is the failure mode this whole script exists to answer, and the
// repository has now shipped that shape twice: a materials assertion that
// compared 0 to 0 sixty times and called it 60/60, and a routine written into
// HANDOFF three times that never once ran.
//
// What it catches, against the three incidents that have actually happened:
//
//   1. The deployed Edge Function bundle behind disk. `generate-plan` sat two
//      versions stale for a fortnight and that, not the prompt, is why Phase 3
//      failed 11 of 20 — the fix existed in the repo and had never shipped.
//      Needs SUPABASE_ACCESS_TOKEN; without it this half reports UNVERIFIED and
//      the script exits 2.
//   2. A filename that does not match the stamped version. `apply_migration`
//      chooses its own version, so the committed name and the applied one are
//      two separate strings that nothing reconciles. Caught as a local-only
//      version plus a remote-only version, in one run.
//   3. A migration applied and never committed. Caught as remote-only.
//
// Incident 3 is why this is a script you run rather than a pre-commit hook: the
// session that orphaned those two migrations **never made a commit at all**, so
// no commit-triggered check could have fired. A control that only runs when you
// remember to commit does not cover the case where you forgot to.
//
// No dependencies, by design — same rule as csv_to_sql.mjs.

import { readFileSync, readdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SUPABASE_DIR = dirname(fileURLToPath(import.meta.url));
const ROOT = join(SUPABASE_DIR, '..');
const MIGRATIONS_DIR = join(SUPABASE_DIR, 'migrations');
const FUNCTIONS_DIR = join(SUPABASE_DIR, 'functions');

// Set before anything prints: in --hook mode stdout must be JSON and nothing else.
const asHook = process.argv.includes('--hook');

const problems = [];
const unverified = [];

function loadEnv() {
  const raw = readFileSync(join(ROOT, 'apps', 'mobile', '.env'), 'utf8');
  const env = {};
  for (const line of raw.split(/\r?\n/)) {
    const match = /^([A-Z_]+)=(.*)$/.exec(line.trim());
    if (match) env[match[1]] = match[2].trim();
  }
  return env;
}

/**
 * Strips SQL line and block comments, including inside `$$ … $$` bodies.
 *
 * Single-quoted strings are left alone, because a `--` in one is data.
 *
 * Comments inside function bodies were kept at first, on the reasoning that
 * Postgres stores the body verbatim so a body with different comments really is
 * a different `prosrc`. True, and it made the check useless: five migrations
 * lit up as "the SQL differs — a fresh db push would build a different
 * database" when the only difference was the header prose those sessions did
 * not paste inline. **Nothing about behaviour differed in any of them.**
 *
 * A check that reports five false alarms on a clean repo gets ignored, and an
 * ignored check is the thing this script replaced. So the rule is: comments
 * never execute, therefore comments are never drift. A prose difference is
 * counted and reported as a note; only executable SQL is allowed to fail the
 * run.
 */
function stripSqlComments(sql) {
  let out = '';
  let i = 0;

  while (i < sql.length) {
    if (sql[i] === "'") {
      out += sql[i];
      i += 1;
      while (i < sql.length) {
        out += sql[i];
        if (sql[i] === "'") {
          if (sql[i + 1] === "'") {
            out += sql[i + 1];
            i += 2;
            continue;
          }
          i += 1;
          break;
        }
        i += 1;
      }
      continue;
    }

    if (sql[i] === '-' && sql[i + 1] === '-') {
      while (i < sql.length && sql[i] !== '\n') i += 1;
      continue;
    }

    if (sql[i] === '/' && sql[i + 1] === '*') {
      let depth = 1;
      i += 2;
      while (i < sql.length && depth > 0) {
        if (sql.startsWith('/*', i)) { depth += 1; i += 2; }
        else if (sql.startsWith('*/', i)) { depth -= 1; i += 2; }
        else i += 1;
      }
      continue;
    }

    out += sql[i];
    i += 1;
  }

  return out;
}

/** What the database stores: LF-joined, no trailing newline. */
const rawDigest = (text) =>
  createHash('md5')
    .update(text.replace(/\r\n/g, '\n').replace(/\n+$/, ''), 'utf8')
    .digest('hex');

/**
 * The statement, ignoring prose.
 *
 * Two digests rather than one, because the two kinds of difference are not the
 * same finding and conflating them makes the check useless. Thirteen migrations
 * in this repo already differ from what was applied **only in their comment
 * blocks** — `apply_migration` takes SQL inline, and earlier sessions passed the
 * statements without the long headers the committed file carries. That is a
 * documentation gap, not a database that disagrees with the repo, and reporting
 * thirteen scary mismatches on every run is how a check gets ignored.
 *
 * A difference *here* means the SQL itself differs, which is the one that
 * matters: it means a fresh `db push` would build a different database.
 */
const sqlDigest = (text) =>
  createHash('md5')
    .update(
      stripSqlComments(text)
        // Postgres concatenates two string literals separated by whitespace
        // containing a newline, which is how every long `comment on` in this
        // repo is wrapped. `'a ' \n 'b'` and `'a b'` are the same value, so a
        // file that wraps and an applied statement that did not are not drift.
        // The newline is required by Postgres, so requiring it here too keeps
        // this from mangling anything else.
        .replace(/'[ \t]*\r?\n\s*'/g, '')
        .replace(/\s+/g, ' ')
        .trim(),
      'utf8',
    )
    .digest('hex');

async function checkMigrations(env) {
  const response = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/migration_ledger`, {
    method: 'POST',
    headers: {
      apikey: env.SUPABASE_ANON_KEY,
      Authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
      'Content-Type': 'application/json',
    },
    body: '{}',
  });

  if (!response.ok) {
    unverified.push(
      `migrations: migration_ledger() returned ${response.status}. ` +
      `${await response.text()}`.slice(0, 300),
    );
    return;
  }

  const remote = await response.json();

  // A precondition, not a formality. An empty ledger would make every
  // comparison below trivially agree with an empty local set, and a project
  // with no migrations is never the real answer here.
  if (!Array.isArray(remote) || remote.length === 0) {
    unverified.push('migrations: the ledger came back empty, which cannot be right.');
    return;
  }

  const local = new Map();
  for (const name of readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql'))) {
    const version = name.slice(0, name.indexOf('_'));
    if (!/^\d{14}$/.test(version)) {
      problems.push(`migrations: ${name} does not start with a 14-digit version`);
      continue;
    }
    if (local.has(version)) {
      problems.push(`migrations: two local files claim version ${version}`);
      continue;
    }
    local.set(version, name);
  }

  if (local.size === 0) {
    unverified.push('migrations: no local migration files found.');
    return;
  }

  const remoteByVersion = new Map(remote.map((r) => [r.version, r]));
  let commentOnly = 0;

  for (const [version, name] of local) {
    if (!remoteByVersion.has(version)) {
      problems.push(
        `migrations: ${name} is committed but NOT APPLIED. ` +
        'Either it was never applied, or it was applied under a different ' +
        'version and the file needs renaming to match (incident 2).',
      );
      continue;
    }

    const applied = remoteByVersion.get(version);
    const file = readFileSync(join(MIGRATIONS_DIR, name), 'utf8');

    if (sqlDigest(file) !== sqlDigest(applied.statements_text)) {
      problems.push(
        `migrations: ${name} — THE SQL DIFFERS from what was applied. ` +
        'A fresh `supabase db push` would build a different database than ' +
        'this one. apply_migration takes SQL inline, so the file and the ' +
        'applied text are two copies and can be edited apart.',
      );
    } else if (rawDigest(file) !== applied.statements_md5) {
      // Same statements, different prose. Worth counting, not worth alarming
      // over: the database is exactly what the file says it is.
      commentOnly += 1;
    }
  }

  for (const { version } of remote) {
    if (!local.has(version)) {
      problems.push(
        `migrations: ${version} is APPLIED but has no committed file. ` +
        'Recover it from supabase_migrations.schema_migrations and commit it ' +
        '(incident 3) — a fresh checkout cannot reproduce this database.',
      );
    }
  }

  if (!asHook) console.log(
    `  migrations   ${local.size} local, ${remote.length} applied` +
    `${problems.length === 0 ? ' — SQL agrees' : ''}`,
  );
  if (commentOnly > 0 && !asHook) {
    console.log(
      `               (${commentOnly} differ in comments only — the SQL is ` +
      'identical, so the database matches the repo)',
    );
  }
}

function localFunctionFiles(slug) {
  // The deploy bundle is rooted at supabase/functions, so a function's own
  // directory plus _shared is what gets shipped. Test files are not deployed.
  const files = new Map();
  const collect = (dir, prefix) => {
    for (const entry of readdirSync(join(FUNCTIONS_DIR, dir), { withFileTypes: true })) {
      if (!entry.isFile()) continue;
      if (!entry.name.endsWith('.ts')) continue;
      if (entry.name.endsWith('_test.ts')) continue;
      files.set(
        `${prefix}${entry.name}`,
        readFileSync(join(FUNCTIONS_DIR, dir, entry.name), 'utf8'),
      );
    }
  };
  collect(slug, `${slug}/`);
  collect('_shared', '_shared/');
  return files;
}

/**
 * The Supabase personal access token, from the environment or from a file in
 * the home directory.
 *
 * **Deliberately never from inside the repository.** A PAT has account-level
 * access — it can create and delete projects — and this repo is public. It has
 * already had one credential committed and caught by GitGuardian, so the answer
 * is not "another gitignored file"; it is a path that a `git add -A` cannot
 * reach even by accident.
 *
 * The environment variable is safest of all, because it dies with the shell.
 * The file exists because a control that only runs when someone remembers to
 * export a variable is the habit that failed three times — see CLAUDE.md.
 */
function accessToken() {
  if (process.env.SUPABASE_ACCESS_TOKEN) return process.env.SUPABASE_ACCESS_TOKEN.trim();
  const path = join(homedir(), '.amora-drift-token');
  try {
    return readFileSync(path, 'utf8').trim() || null;
  } catch {
    return null;
  }
}

async function checkEdgeFunctions(env) {
  const token = accessToken();
  if (!token) {
    unverified.push(
      'edge functions: no access token, so the deployed bundles were NOT ' +
      'compared against disk. This is the half that catches incident 1. ' +
      'Create one at https://supabase.com/dashboard/account/tokens, then ' +
      'either export SUPABASE_ACCESS_TOKEN or write it to ' +
      `${join(homedir(), '.amora-drift-token')} — never inside this repo, ` +
      'which is public.',
    );
    return;
  }

  const ref = new URL(env.SUPABASE_URL).hostname.split('.')[0];
  const api = (path) =>
    fetch(`https://api.supabase.com/v1/projects/${ref}${path}`, {
      headers: { Authorization: `Bearer ${token}` },
    });

  const listed = await api('/functions');
  if (!listed.ok) {
    unverified.push(`edge functions: list returned ${listed.status}`);
    return;
  }
  const functions = await listed.json();
  if (!Array.isArray(functions) || functions.length === 0) {
    unverified.push('edge functions: none listed, which cannot be right.');
    return;
  }

  for (const fn of functions) {
    const bodyResponse = await api(`/functions/${fn.slug}/body`);
    if (!bodyResponse.ok) {
      unverified.push(
        `edge functions: ${fn.slug} body returned ${bodyResponse.status}`);
      continue;
    }

    let deployed;
    try {
      const parsed = await bodyResponse.json();
      const list = Array.isArray(parsed) ? parsed : parsed?.files;
      if (!Array.isArray(list)) throw new Error('unrecognised shape');
      deployed = new Map(list.map((f) => [f.name, f.content]));
    } catch {
      // Never fall through to a pass. If the response shape is not what this
      // script understands, that is "could not check", not "matches".
      unverified.push(
        `edge functions: ${fn.slug} body came back in a shape this script does ` +
        'not understand, so nothing was compared.',
      );
      continue;
    }

    const local = localFunctionFiles(fn.slug);
    const normalise = (s) => s.replace(/\r\n/g, '\n');

    for (const [name, content] of local) {
      if (!deployed.has(name)) {
        problems.push(`edge functions: ${fn.slug} v${fn.version} is missing ${name}`);
      } else if (normalise(deployed.get(name)) !== normalise(content)) {
        problems.push(
          `edge functions: ${fn.slug} v${fn.version} has a STALE ${name} — ` +
          'the deployed bundle differs from the repo (incident 1). Redeploy.',
        );
      }
    }
    if (!asHook) console.log(`  ${fn.slug.padEnd(14)} v${fn.version}, ${local.size} files compared`);
  }
}

/**
 * `--hook` mode: emit the Claude Code SessionStart envelope instead of prose.
 *
 * The verdict goes in `additionalContext`, which is injected into the model's
 * context at session start — so drift is something Claude is *told*, not
 * something it has to remember to look for. That is the whole difference
 * between this and the three CLAUDE.md notes that never held.
 *
 * **Always exits 0 in hook mode**, deliberately. A non-zero SessionStart hook
 * risks interfering with startup, and the failure does not need an exit code to
 * be loud — it needs to be *read*, which is what additionalContext does. The
 * verdict word is in the text.
 *
 * The JSON is built here rather than piped through jq because jq is not
 * installed on this machine and node always is.
 */
function hookEnvelope() {
  const verdict = problems.length > 0
    ? 'DRIFT'
    : unverified.length > 0
      ? 'COULD NOT CHECK'
      : 'AGREES';

  const lines = [`check-drift.mjs: ${verdict}`];
  for (const problem of problems) lines.push(`  DRIFT: ${problem}`);
  for (const item of unverified) lines.push(`  UNVERIFIED: ${item}`);

  if (verdict === 'DRIFT') {
    lines.push(
      '',
      'The repository and the Supabase project disagree. Tell Nat before doing',
      'anything else, and do not treat this as a pass.',
    );
  } else if (verdict === 'COULD NOT CHECK') {
    lines.push(
      '',
      'Part of the check could not run, which is NOT a pass. Report it.',
    );
  }

  return JSON.stringify({
    systemMessage: `Amora drift check: ${verdict}`,
    suppressOutput: true,
    hookSpecificOutput: {
      hookEventName: 'SessionStart',
      additionalContext: lines.join('\n'),
    },
  });
}

const env = loadEnv();

if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) {
  unverified.push('apps/mobile/.env is missing SUPABASE_URL or SUPABASE_ANON_KEY.');
  if (asHook) {
    console.log(hookEnvelope());
  } else {
    console.error('apps/mobile/.env is missing SUPABASE_URL or SUPABASE_ANON_KEY.');
    process.exitCode = 2;
  }
} else {
  if (!asHook) console.log('\n  Checking the repository against the project.\n');

  await checkMigrations(env);
  await checkEdgeFunctions(env);

  if (asHook) {
    console.log(hookEnvelope());
  } else {
    if (problems.length > 0) {
      console.log(`\n  DRIFT — ${problems.length} problem(s):\n`);
      for (const problem of problems) console.log(`    ${problem}`);
    }
    if (unverified.length > 0) {
      console.log(`\n  COULD NOT CHECK — ${unverified.length} item(s):\n`);
      for (const item of unverified) console.log(`    ${item}`);
    }

    if (problems.length > 0) {
      process.exitCode = 1;
    } else if (unverified.length > 0) {
      console.log('\n  Nothing checked disagreed, but the run was incomplete.\n');
      process.exitCode = 2;
    } else {
      console.log('\n  The repository and the project agree.\n');
    }
  }
}
