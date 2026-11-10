-- Premium items only show when bought, the paid list in sync_profile, and the
-- gold flag. Any wrong result raises.
\set ON_ERROR_STOP on

create or replace function t_uid(n integer) returns uuid language sql immutable as $$
  select ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid
$$;
create or replace function t_as(n integer) returns void language sql as $$
  select set_config('request.jwt.claim.sub', t_uid(n)::text, false)
$$;
create or replace function t_eq(got anyelement, want anyelement, what text) returns void
language plpgsql as $$
begin
  if got is distinct from want then
    raise exception 'FAIL %: expected %, got %', what, want, got;
  end if;
  raise notice 'ok   %', what;
end $$;

insert into auth.users (id) values (t_uid(601)), (t_uid(602));
insert into players (id, name) values (t_uid(601), 'Buyer'), (t_uid(602), 'Faker');
-- Player 601 bought the bolt flyer and the neon world, and turned 2 diamonds into gold.
insert into diamond_ledger (player_id, amount, reason, ref) values
  (t_uid(601), 20, 'daily_prize', '2026-11-01'),
  (t_uid(601), -20, 'item', 'flyer:bolt'),
  (t_uid(601), 30, 'daily_prize', '2026-11-02'),
  (t_uid(601), -30, 'item', 'world:neon'),
  (t_uid(601), -2, 'convert', '');
insert into runs (player_id, score, day, played_at, gameplay_version, seed, status, coins)
values
  (t_uid(601), 10, current_date, now(), 14, 1, 'ok', 40),
  (t_uid(601), 12, current_date, now(), 14, 2, 'pending', 10),
  (t_uid(601), 99, current_date, now(), 14, 3, 'rejected', 5000);

do $$
declare
  look jsonb := '{"flyer": "bolt", "world": "neon", "trail": "sparks", "plate": 3}';
  r jsonb;
begin
  perform t_eq(
    spikey_paid_loadout(t_uid(601), look), look, 'a buyer keeps every item'
  );
  perform t_eq(
    spikey_paid_loadout(t_uid(602), look), '{"trail": "sparks", "plate": 3}'::jsonb,
    'unbought premium items are dropped, the rest stays'
  );
  perform t_eq(spikey_paid_loadout(t_uid(602), null), '{}'::jsonb, 'no loadout');

  insert into runs (player_id, score, day, played_at, gameplay_version, seed, loadout)
  values (t_uid(602), 5, current_date, now(), 14, 9, look);
  perform t_eq(
    (select loadout from runs where player_id = t_uid(602)),
    '{"trail": "sparks", "plate": 3}'::jsonb, 'a sent run shows only what was bought'
  );

  update players set flyer = 'nova' where id = t_uid(602);
  perform t_eq(
    (select flyer from players where id = t_uid(602)), 'buzz', 'an unbought flyer on the boards'
  );
  update players set flyer = 'bolt' where id = t_uid(601);
  perform t_eq((select flyer from players where id = t_uid(601)), 'bolt', 'a bought one');
  update players set flyer = 'dash' where id = t_uid(602);
  perform t_eq((select flyer from players where id = t_uid(602)), 'dash', 'a gold flyer');

  perform t_as(601);
  r := sync_profile('{"coins": 100}', 0);
  perform t_eq(r -> 'paid', '["flyer:bolt", "world:neon"]'::jsonb, 'the bought items come back');
  perform t_eq(
    (select gold_excess from profiles where player_id = t_uid(601)), 0::bigint,
    'gold within the runs (40 + 10) and the conversion (200)'
  );
  r := sync_profile('{"coins": 1000}', 1);
  perform t_eq(r ->> 'status', 'saved', 'too much gold is still saved');
  perform t_eq(
    (select gold_excess from profiles where player_id = t_uid(601)), 750::bigint,
    'and flagged: a rejected run counts for nothing'
  );
  r := sync_profile('{"coins": 1}', 1);
  perform t_eq(r -> 'paid', '["flyer:bolt", "world:neon"]'::jsonb, 'a conflict carries them too');

  perform t_as(602);
  r := sync_profile('{"coins": "lots"}', 0);
  perform t_eq(r -> 'paid', '[]'::jsonb, 'nothing bought');
  perform t_eq(
    (select gold_excess from profiles where player_id = t_uid(602)), 0::bigint,
    'gold that is not a number counts as none'
  );

  perform t_eq(
    has_function_privilege('authenticated', 'public.spikey_paid_loadout(uuid, jsonb)', 'execute'),
    false, 'the helpers are not callable from the game'
  );
end $$;

select 'ALL DATABASE TESTS PASSED' as result;
