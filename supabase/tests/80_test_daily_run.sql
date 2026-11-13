-- Daily Run: the day's map, tries, its board, locked replays and the payout.
-- Players 901..912 (no other test uses them). Any wrong result raises.
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
-- A checked Daily Run run of day p_day for player n, played p_hours after noon.
create or replace function t_drun(n integer, p_score integer, p_day date, p_status text,
                                  p_hours integer default 0) returns bigint
language sql as $$
  insert into runs (player_id, score, day, played_at, gameplay_version, seed, season,
                    status, board)
  select t_uid(n), p_score, p_day,
         p_day::timestamp + interval '12 hours' + make_interval(hours => p_hours),
         23, d.seed, d.season, p_status, 'daily_run'
  from spikey_daily_run_of(p_day) d
  returning id
$$;

insert into auth.users (id) select t_uid(n) from generate_series(901, 912) n;
insert into players (id, name) select t_uid(n), 'Daily' || n from generate_series(901, 912) n;

do $$
declare
  t date := spikey_today();
  y date := spikey_today() - 1;
  d jsonb;
  tr1 jsonb;
  tr2 jsonb;
  b jsonb;
  w jsonb;
  c jsonb;
  failed boolean;
  v_run bigint;
  v_seed bigint;
begin
  perform t_eq(spikey_board_zone(), 'Europe/Amsterdam', 'both daily boards share one clock');
  perform t_eq(spikey_daily_run_prize(1), spikey_daily_prize(1), 'Daily Run pays Today''s tiers');
  perform t_eq(
    (select sum(spikey_daily_run_prize(n))::integer from generate_series(1, 12) n), 14,
    '14 more diamonds a day'
  );

  -- The season of a date, as SeasonCalendar.for_date.
  perform t_eq(spikey_season_of(date '2026-10-05'), 0, 'October is Halloween');
  perform t_eq(spikey_season_of(date '2026-12-24'), 1, 'December is Winter');
  perform t_eq(spikey_season_of(date '2027-01-07'), 5, '7 January is New Year');
  perform t_eq(spikey_season_of(date '2027-01-08'), -1, '8 January is none');
  perform t_eq(spikey_season_of(date '2027-02-14'), 2, '14 February is Valentine');
  perform t_eq(spikey_season_of(date '2027-02-15'), -1, '15 February is none');
  perform t_eq(spikey_season_of(date '2027-04-30'), 3, 'April is Spring');
  perform t_eq(spikey_season_of(date '2027-08-01'), 4, 'August is Summer');
  perform t_eq(spikey_season_of(date '2026-11-13'), -1, 'November is none');

  -- Today's Daily Run, before any try.
  perform t_as(901);
  d := get_daily_run();
  perform t_eq((d->>'tries_used')::integer, 0, 'no tries yet');
  perform t_eq((d->>'tries_max')::integer, 3, 'three tries a day');
  perform t_eq((d->>'number')::integer, (t - spikey_daily_run_epoch()) + 1, 'the day''s number');
  perform t_eq((d->>'season')::integer, spikey_season_of(t), 'played in the day''s season');
  perform t_eq(d ? 'seed', false, 'the seed only comes with a try');
  perform t_eq(d->'best', 'null'::jsonb, 'no best yet');
  perform t_eq(d->>'resets_in_s' is not null, true, 'it says when it resets');

  -- One map for everyone; another day, another map.
  tr1 := start_daily_try('Daily901', 'buzz');
  perform t_eq((tr1->>'n')::integer, 1, 'first try');
  v_seed := (tr1->>'seed')::bigint;
  perform t_eq(v_seed, (select seed from daily_runs where day = t), 'the try plays today''s seed');
  perform t_as(902);
  tr2 := start_daily_try('Daily902', 'buzz');
  perform t_eq((tr2->>'seed')::bigint, v_seed, 'the same seed for every player');
  perform t_eq((spikey_daily_run_of(t + 1)).seed <> v_seed, true, 'tomorrow has another seed');
  perform t_eq((spikey_daily_run_of(t)).seed, v_seed, 'asking again keeps the day''s seed');

  -- Three tries, then no more.
  perform t_as(901);
  perform start_daily_try('Daily901', 'buzz');
  perform t_eq((start_daily_try('Daily901', 'buzz')->>'n')::integer, 3, 'third try');
  begin
    perform start_daily_try('Daily901', 'buzz');
    failed := false;
  exception when others then
    failed := sqlerrm like '%no tries left%';
  end;
  perform t_eq(failed, true, 'a fourth try is refused');
  perform t_eq((get_daily_run()->>'tries_used')::integer, 3, 'all three used');

  -- Sending a try.
  begin
    perform submit_daily_run((tr1->>'try')::uuid, 'Daily901', 'buzz', 40, 23, v_seed + 1, '[1]');
    failed := false;
  exception when others then
    failed := sqlerrm like '%map%';
  end;
  perform t_eq(failed, true, 'another seed is refused');
  begin
    perform submit_daily_run(
      (tr1->>'try')::uuid, 'Daily901', 'buzz', 40, 23, v_seed, '[1]', null,
      spikey_season_of(t) + 1
    );
    failed := false;
  exception when others then
    failed := sqlerrm like '%map%';
  end;
  perform t_eq(failed, true, 'another season is refused');
  perform submit_daily_run(
    (tr1->>'try')::uuid, 'Daily901', 'buzz', 40, 23, v_seed, '[1, 2]', null, spikey_season_of(t),
    3, 900
  );
  v_run := (select run_id from daily_tries where id = (tr1->>'try')::uuid);
  perform t_eq((select board from runs where id = v_run), 'daily_run', 'stored on the Daily Run');
  perform t_eq((select day from runs where id = v_run), t, 'on the try''s day');
  perform t_eq((select revives from runs where id = v_run), '[]'::jsonb, 'with no revives');
  begin
    perform submit_daily_run((tr1->>'try')::uuid, 'Daily901', 'buzz', 41, 23, v_seed, '[1]');
    failed := false;
  exception when others then
    failed := sqlerrm like '%already sent%';
  end;
  perform t_eq(failed, true, 'a try is sent once');
  perform t_as(902);
  begin
    perform submit_daily_run(
      (select id from daily_tries where player_id = t_uid(901) and day = t and n = 2),
      'Daily902', 'buzz', 99, 23, v_seed, '[1]'
    );
    failed := false;
  exception when others then
    failed := sqlerrm like '%unknown try%';
  end;
  perform t_eq(failed, true, 'nobody sends another player''s try');

  -- The board: own pending run shows to its player only; others are locked.
  perform t_as(901);
  b := get_board('daily_run');
  perform t_eq((b->'me'->>'score')::integer, 40, 'my try is on the Daily Run board');
  perform t_eq((b->'entries'->0->>'run')::bigint, v_run, 'my own row has its replay');
  perform t_eq(get_board('daily')->'me', 'null'::jsonb, 'a Daily Run run is not on Today');
  perform t_eq(get_board('all_time')->'me', 'null'::jsonb, 'nor on All-time');
  perform t_eq((get_daily_run()->>'best')::integer, 40, 'my best today');
  perform t_eq((get_daily_run()->>'rank')::integer, 1, 'my rank today');
  perform t_as(902);
  perform t_eq(jsonb_array_length(get_board('daily_run')->'entries'), 0,
               'a run waiting for the checker shows to its player only');
  update runs set status = 'ok' where id = v_run;
  b := get_board('daily_run');
  perform t_eq(b->'entries'->0->>'name', 'Daily901', 'a checked try shows to everyone');
  perform t_eq(b->'entries'->0->'run', 'null'::jsonb, 'its replay is locked today');
  perform t_eq((b->'entries'->0->>'locked')::boolean, true, 'and marked locked');
  perform t_eq(get_run(v_run), null::jsonb, 'get_run keeps today''s Daily Run locked');
  perform t_as(901);
  perform t_eq(get_run(v_run) is not null, true, 'but plays for its own player');

  -- An endless run stays off the Daily Run board.
  perform submit_run('Daily901', 'buzz', 77, 23, 5, '[1]');
  perform t_eq((get_board('daily')->'me'->>'score')::integer, 77, 'an endless run is on Today');
  perform t_eq((get_board('daily_run')->'me'->>'score')::integer, 40, 'and not on the Daily Run');

  -- Yesterday's Daily Run: 901 100, 902 and 903 95 (902 earlier), 904..911
  -- 84 - n, 912 a rejected 999, and one still waiting.
  perform t_drun(901, 100, y, 'ok');
  perform t_drun(901, 20, y, 'ok');
  perform t_drun(902, 95, y, 'ok', 0);
  perform t_drun(903, 95, y, 'ok', 1);
  for n in 904..911 loop
    perform t_drun(n, 84 - n, y, 'ok');
  end loop;
  perform t_drun(912, 999, y, 'rejected');
  v_run := t_drun(912, 5, y, 'pending');
  w := get_wallet();
  perform t_eq((select count(*)::integer from daily_run_prizes where day = y), 0,
               'no payout while a run of that day waits');
  update runs set status = 'ok' where id = v_run;
  w := get_wallet();
  perform t_eq((select count(*)::integer from daily_run_prizes where day = y), 10,
               'ten places paid');
  perform t_eq((select sum(diamonds)::integer from daily_run_prizes where day = y), 14,
               '14 diamonds');
  perform t_eq((select rank from daily_run_prizes where day = y and player_id = t_uid(902)), 2,
               'on a tie the earlier run is 2nd');
  perform t_eq((select rank from daily_run_prizes where day = y and player_id = t_uid(903)), 3,
               'the later one 3rd');
  perform t_eq((select count(*)::integer from daily_run_prizes
                where day = y and player_id = t_uid(912)), 0, 'the rejected 999 wins nothing');
  perform t_eq((select count(*)::integer from daily_prizes
                where day = y and player_id between t_uid(901) and t_uid(912)), 0,
               'Daily Run runs win nothing on Today');
  perform t_eq((
    select x->>'board' from jsonb_array_elements(w->'prizes') x where x->>'board' = 'daily_run'
  ), 'daily_run', 'the wallet lists the Daily Run prize');
  perform t_eq((
    select (x->>'diamonds')::integer from jsonb_array_elements(w->'prizes') x
    where x->>'board' = 'daily_run'
  ), 3, 'first place pays 3');
  perform t_eq((
    select (x->>'number')::integer from jsonb_array_elements(w->'prizes') x
    where x->>'board' = 'daily_run'
  ), (y - spikey_daily_run_epoch()) + 1, 'with the day''s number');

  d := get_daily_run();
  perform t_eq((d->'yesterday'->'me'->>'rank')::integer, 1, 'yesterday''s place');
  perform t_eq((d->'yesterday'->>'settled')::boolean, true, 'yesterday is paid');
  perform t_eq(jsonb_array_length(d->'yesterday'->'top'), 3, 'yesterday''s top three');
  perform t_eq(d->'yesterday'->'top'->1->>'name', 'Daily902', 'in order');
  perform t_as(902);
  perform t_eq(
    get_run((d->'yesterday'->'top'->0->>'run')::bigint) is not null, true,
    'yesterday''s replays are open'
  );

  perform t_as(901);
  c := claim_prizes();
  perform t_eq((c->>'claimed')::integer >= 3, true, 'claiming adds the Daily Run prize');
  perform t_eq((select count(*)::integer from diamond_ledger
                where player_id = t_uid(901) and reason = 'daily_run_prize'), 1,
               'one ledger line for it');
  perform t_eq((select count(*)::integer from daily_run_prizes
                where player_id = t_uid(901) and claimed_at is null), 0, 'and it is claimed');
  perform get_wallet();
  perform t_eq((select count(*)::integer from daily_run_settled where day = y), 1,
               'a day pays once');

  perform t_eq(
    has_function_privilege('authenticated', 'public.spikey_daily_run_of(date)', 'execute'),
    false, 'players cannot make a day''s map'
  );
  perform t_eq(
    has_function_privilege('authenticated', 'public.spikey_settle_daily_runs()', 'execute'),
    false, 'nor pay a day'
  );
  perform t_eq(
    has_function_privilege('anon', 'public.start_daily_try(text, text)', 'execute'),
    false, 'signed-out callers cannot start a try'
  );
  perform t_eq(
    has_function_privilege('authenticated', 'public.start_daily_try(text, text)', 'execute'),
    true, 'players can'
  );
end $$;

select 'ALL DATABASE TESTS PASSED' as result;
