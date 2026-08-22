-- Removes every generated demo row. One command.
--
--   Run it in the Supabase SQL editor, or:
--     supabase db execute --file supabase/seed/wipe-demo.sql
--
-- `verified_method = 'generated'` is the key rather than the slug prefix,
-- because the constraint on the column is enforced by the database while a slug
-- is just text. csv_to_sql.mjs refuses to import a row where the two disagree in
-- either direction, so the prefix and the method always name the same set.
--
-- place_notes and place_reports cascade. plan_items.place_id is SET NULL, so a
-- saved plan built on demo rows would survive as stops with no place — which the
-- Dart model's non-nullable Place cannot parse. Any such plan is deleted first,
-- and its price reports before that, because place_reports_price_needs_a_plan
-- forbids a priced report whose plan has gone.

begin;

-- 1. Price reports belonging to plans that stand on demo rows.
delete from public.place_reports pr
where pr.plan_id in (
  select distinct pi.plan_id
  from public.plan_items pi
  join public.places p on p.id = pi.place_id
  where p.verified_method = 'generated'
);

-- 2. Memories of those plans.
delete from public.memories m
where m.plan_id in (
  select distinct pi.plan_id
  from public.plan_items pi
  join public.places p on p.id = pi.place_id
  where p.verified_method = 'generated'
);

-- 3. The plans themselves.
delete from public.plans pl
where pl.id in (
  select distinct pi.plan_id
  from public.plan_items pi
  join public.places p on p.id = pi.place_id
  where p.verified_method = 'generated'
);

-- 4. The demo places. place_notes and any remaining place_reports cascade.
delete from public.places where verified_method = 'generated';

-- 5. The demo fares. These are the generated matrix, not curated rows — every
--    curated fare carries a verified_at set by hand on the day it was checked.
delete from public.transit_fares
where mode = 'tricycle'
  and from_area in (
    'Poblacion', 'Lolomboy', 'Igulot', 'Wakas', 'Tambobong', 'Bambang',
    'Turo', 'Biñang 2nd', 'Bunlo', 'Antipona', 'Taal'
  );

-- 6. Cached plans. They key on places_version(), which moves when curated places
--    change, so they would expire anyway — this just makes it immediate.
delete from public.plan_cache;

select
  (select count(*) from public.places where verified_method = 'generated') as demo_places_left,
  (select count(*) from public.places) as places_left,
  (select count(*) from public.transit_fares) as fares_left;

commit;
