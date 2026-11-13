-- spikey_reset_boards (20261113120000_reset_boards.sql): every run is gone and
-- the boards are empty, but earned prizes, streaks, the Earn screen's best and
-- the gold ceiling stay. Runs last: it deletes every run of the other tests too.
-- Any wrong result raises.
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
create or replace function t_run(
  n integer, p_score integer, p_day date, p_status text, p_coins integer
) returns void language sql as $$
  insert into runs (player_id, score, day, played_at, gameplay_version, seed, status, coins)
  values (
    t_uid(n), p_score, p_day, p_day::timestamp + interval '12 hours', 22, 1, p_status, p_coins
  )
$$;

insert into auth.users (id) select t_uid(n) from generate_series(801, 803) n;
insert into players (id, name) select t_uid(n), 'Reset' || n from generate_series(801, 803) n;

do $$
declare
  t date := spikey_today();
  b jsonb;
  s jsonb;
  v_deleted integer;
begin
  -- A finished day nobody settled yet (earlier tests may have settled it).
  delete from settled_days where day = t - 6;
  -- 801: a checked run on each of the last 7 days (10 coins each), and a top
  -- score of 99999 (500 coins) six days ago. No prize written yet.
  for d in 0..6 loop
    perform t_run(801, 30, t - d, 'ok', 10);
  end loop;
  perform t_run(801, 99999, t - 6, 'ok', 500);
  -- 802: a rejected run (its coins never count) and one still waiting.
  perform t_run(802, 50, t, 'rejected', 1000);
  perform t_run(802, 40, t, 'pending', 200);
  -- Today's remembered place and an alert not sent yet.
  insert into spot_state (player_id, day, place) values (t_uid(801), t, 1)
  on conflict (player_id) do update set day = excluded.day, place = excluded.place;
  insert into spot_alerts (player_id, day, line, title, body)
  values (t_uid(801), t, 'first', 'Knocked off 1st', 'Someone beat you.');

  v_deleted := spikey_reset_boards();
  perform t_eq(v_deleted >= 10, true, 'the reset deletes the runs');
  perform t_eq((select count(*)::integer from runs), 0, 'no run is left');

  -- Earned before the reset: paid out and still claimable.
  perform t_eq(
    (select count(*)::integer from daily_prizes
     where player_id = t_uid(801) and day = t - 6 and claimed_at is null),
    1, 'the unsettled day was settled with the old runs'
  );
  perform t_eq(
    (select count(*)::integer from bonus_prizes
     where player_id = t_uid(801) and kind = 'milestone'),
    4, 'every milestone reached before the reset is written'
  );
  perform t_eq(
    (select count(*)::integer from bonus_prizes
     where player_id = t_uid(801) and kind = 'streak'),
    1, 'the 7-day streak diamond is written'
  );

  -- The boards are empty.
  perform t_as(801);
  b := get_board('all_time');
  perform t_eq(b->'entries', '[]'::jsonb, 'the All-time board is empty');
  perform t_eq((b->>'players')::integer, 0, 'with nobody on it');
  perform t_eq(b->'me', 'null'::jsonb, 'and no place for the caller');
  b := get_board('daily');
  perform t_eq(b->'entries', '[]'::jsonb, 'the Daily board is empty');

  -- Carried: the Earn screen, streaks and the gold ceiling go on.
  s := get_earn_status();
  perform t_eq((s->>'best')::integer, 99999, 'the Earn best is kept');
  perform t_eq(s->'milestones', '[25, 50, 75, 100]'::jsonb, 'milestones are kept');
  perform t_eq((s->>'streak')::integer, 7, 'the streak is kept');
  perform t_eq((s->>'played_today')::boolean, true, 'today still counts as played');
  perform t_eq((s->>'streak_won')::integer, 1, 'and its streak diamond');
  perform t_eq(spikey_gold_ceiling(t_uid(801)), 570::bigint, 'the gold ceiling is kept');
  perform t_eq(
    spikey_gold_ceiling(t_uid(802)), 200::bigint, 'rejected coins still never count'
  );
  perform t_eq(
    (select count(*)::integer from spot_state where player_id = t_uid(801)),
    0, 'remembered places are cleared'
  );
  perform t_eq(
    (select count(*)::integer from spot_alerts
     where player_id = t_uid(801) and status = 'queued'),
    0, 'queued alerts are never sent'
  );

  -- A new run starts the boards again, from its own score.
  perform t_run(801, 40, t, 'ok', 5);
  b := get_board('all_time');
  perform t_eq((b->'me'->>'score')::integer, 40, 'the new board has only the new run');
  perform t_eq(spikey_gold_ceiling(t_uid(801)), 575::bigint, 'new coins add to the carry');
  s := get_earn_status();
  perform t_eq((s->>'streak')::integer, 7, 'a new run today keeps the streak');

  -- A second reset adds to the carry instead of losing it.
  perform spikey_reset_boards();
  perform t_eq(spikey_gold_ceiling(t_uid(801)), 575::bigint, 'a second reset keeps the coins');
  s := get_earn_status();
  perform t_eq((s->>'best')::integer, 99999, 'and the best');

  perform t_eq(
    has_function_privilege('authenticated', 'public.spikey_reset_boards()', 'execute'),
    false, 'players cannot reset the boards'
  );
  perform t_eq(
    has_function_privilege('anon', 'public.spikey_reset_boards()', 'execute'),
    false, 'nor can signed-out callers'
  );
end $$;

select 'ALL DATABASE TESTS PASSED' as result;
