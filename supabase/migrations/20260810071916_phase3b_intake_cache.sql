-- Phase 3b — intake_cache.
--
-- §7 step 0 reduces free text to the constraint record before anything is
-- hashed, which is the whole reason a conversational intake is affordable on a
-- free tier: step 2 keeps hashing exactly what it always hashed. This table is
-- the other half of that economy — it stops the *extraction* call repeating for
-- utterances that differ only in wording.
--
-- Two model calls now exist per new utterance rather than one. Three things
-- hold that down and this is one of them; the other two are starter chips
-- (which skip extraction entirely, because a chip is already a structured
-- value) and plan_cache, which still absorbs repeat constraints regardless of
-- the words that produced them.
--
-- SHARED ACROSS USERS, deliberately, and §5 states the reason: an utterance
-- carries no personal data once reduced to a budget, a time bucket and a
-- barangay. What is stored is the constraint record, never the sentence — the
-- hash is one-way and the text is not kept.
--
-- No policies, exactly like plan_cache. RLS on with zero policies denies every
-- role except the service role the Edge Function runs as, which is the intent:
-- a shared cache is server infrastructure, not user data. This will be flagged
-- by the security advisor as `rls_enabled_no_policy` and that is expected —
-- HANDOFF lists it under known-permanent noise for plan_cache already.

create table public.intake_cache (
  id uuid primary key default gen_random_uuid(),

  -- SHA-256 of the normalised utterance. Normalisation (lowercase, collapse
  -- whitespace, strip punctuation) is what makes "under 200 tonight" and
  -- "Under ₱200, tonight!" one entry instead of two.
  utterance_hash text not null unique,

  -- The step-1 record: budget, time, origin, occasion. Never a place name —
  -- the extraction schema has no field one could occupy (invariant 1).
  constraints jsonb not null,

  hit_count integer not null default 0,
  created_at timestamptz not null default now()
);

comment on table public.intake_cache is
  'Normalised utterance -> constraint record, so repeat phrasings cost no model '
  'call. Shared across users: an utterance carries no personal data once '
  'reduced to a budget, a time bucket and a barangay. Service role only.';

comment on column public.intake_cache.constraints is
  'The §7 step-1 record. Constraint values only — extraction may never emit a '
  'place or activity name, and its responseSchema has nowhere to put one.';

alter table public.intake_cache enable row level security;

-- Deliberately no policies and no grants. See the header.
