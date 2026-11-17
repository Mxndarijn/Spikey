-- Lost-spot alerts against real tables. Any wrong result raises.
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
-- A run that waits for the checker, then passes: the way real runs arrive.
create or replace function t_checked_run(n integer, p_score integer) returns void
language plpgsql as $$
declare
  v_id bigint;
begin
  insert into runs (player_id, score, day, played_at, gameplay_version, seed, status)
  values (t_uid(n), p_score, spikey_today(), now(), 14, 1, 'pending')
  returning id into v_id;
  update runs set status = 'ok' where id = v_id;
end $$;
-- Minutes ahead of UTC that make it `p_hour` o'clock on a phone right now.
create or replace function t_offset_for_hour(p_hour integer) returns integer language sql as $$
  select (((p_hour - extract(hour from now() at time zone 'UTC')::integer + 36) % 24) - 12) * 60
$$;
create or replace function t_alert(n integer, p_line text) returns spot_alerts language sql as $$
  select * from spot_alerts
  where player_id = t_uid(n) and line = p_line and day = spikey_today()
$$;

delete from runs where day = spikey_today();
insert into auth.users (id) select t_uid(n) from generate_series(21, 34) n;
insert into players (id, name) select t_uid(n), 'N' || n from generate_series(21, 34) n;

do $$
declare
  today date := spikey_today();
  pending jsonb;
  failed boolean;
begin
  -- Phones: p21 at noon, p22 at 2 at night, p23 none, p24 with alerts off.
  perform t_as(21);
  perform register_push('token-of-player-21', 'android', t_offset_for_hour(12));
  perform t_as(22);
  perform register_push('token-of-player-22', 'ios', t_offset_for_hour(2));
  perform t_as(24);
  perform register_push('token-of-player-24', 'android', t_offset_for_hour(12));
  perform set_push_enabled(false);
  perform t_eq((select count(*)::integer from push_devices), 3, 'three phones registered');
  perform t_eq((select enabled from push_devices where player_id = t_uid(24)), false,
               'the Board alerts switch is stored');

  -- Today's board: p21 90, p22 85, p23 80, p24 70, p25..p31 60 down to 54.
  perform t_checked_run(21, 90);
  perform t_checked_run(22, 85);
  perform t_checked_run(23, 80);
  perform t_checked_run(24, 70);
  for n in 25..31 loop
    perform t_checked_run(n, 85 - n);
  end loop;
  perform t_eq((select place from spot_state where player_id = t_uid(21)), 1, 'p21 is remembered as 1st');
  perform t_eq((select place from spot_state where player_id = t_uid(30)), 10, 'p30 as 10th');
  perform t_eq((select count(*)::integer from spot_state where day = today), 10,
               'only the top 10 are remembered');
  perform t_eq((select count(*)::integer from spot_alerts), 0,
               'filling the board alerts nobody');

  -- p32 takes 1st with 95: everyone moves down one place.
  perform t_checked_run(32, 95);
  perform t_eq((select count(*)::integer from spot_alerts), 4, 'four players crossed a line');
  perform t_eq((t_alert(21, 'first')).title, 'N32 took 1st with 95', 'lost 1st: who took it');
  perform t_eq((t_alert(21, 'first')).body, 'You''re 2nd now: 2 diamonds instead of 3.',
               'lost 1st: what it costs');
  perform t_eq((t_alert(21, 'first')).status, 'queued', 'at noon the alert is queued');
  perform t_eq((t_alert(22, 'second')).title, 'N21 passed you with 90', 'lost 2nd: who passed');
  perform t_eq((t_alert(22, 'second')).body, 'You''re 3rd now, still 2 diamonds.',
               'lost 2nd: the prize stays');
  perform t_eq((t_alert(22, 'second')).status, 'quiet', 'at night the alert is not sent');
  perform t_eq((t_alert(23, 'podium')).title, 'You''re off the podium', 'lost 3rd');
  perform t_eq((t_alert(23, 'podium')).body, '4th now: 1 diamond instead of 2.', 'lost 3rd: the cost');
  perform t_eq((t_alert(23, 'podium')).status, 'no_device', 'no phone registered');
  perform t_eq((t_alert(30, 'top10')).title, 'You''re out of the top 10', 'lost the top 10');
  perform t_eq((t_alert(30, 'top10')).body, 'Beat 56 to win a diamond back.',
               'lost the top 10: the score to beat');
  perform t_eq((select count(*)::integer from spot_alerts where player_id = t_uid(24)), 0,
               '4th to 5th crosses no line');

  -- p33 takes 1st with 96: p21 2nd -> 3rd, p22 3rd -> 4th, p32 1st -> 2nd.
  perform t_checked_run(33, 96);
  perform t_eq((t_alert(21, 'second')).status, 'queued', 'p21 now also lost 2nd');
  perform t_eq((t_alert(22, 'podium')).status, 'quiet', 'p22 fell off the podium, at night');
  perform t_eq((t_alert(32, 'first')).title, 'N33 took 1st with 96', 'p32 lost 1st in turn');
  perform t_eq((t_alert(24, 'top10')) is null, true, 'p24 is still inside the top 10');

  -- Each line alerts once a day: p21 wins 1st back and loses it again.
  perform t_checked_run(21, 99);
  perform t_eq((select place from spot_state where player_id = t_uid(21)), 1, 'p21 is 1st again');
  perform t_checked_run(34, 100);
  perform t_eq((select count(*)::integer from spot_alerts
                where player_id = t_uid(21) and line = 'first'), 1, 'losing 1st twice alerts once');
  perform t_eq((select count(*)::integer from spot_alerts where player_id = t_uid(21)), 2,
               'p21 has two alerts today');

  -- The sender: only queued alerts of phones with alerts on.
  pending := worker_pending_alerts(50);
  perform t_eq(jsonb_array_length(pending), 2, 'two alerts wait to be sent');
  perform t_eq(pending->0->>'token', 'token-of-player-21', 'with the phone to send to');
  perform t_eq(pending->0->>'title', 'N32 took 1st with 95', 'oldest first');
  perform t_eq(worker_mark_alerts(jsonb_build_array(
                 jsonb_build_object('id', (pending->0->>'id')::bigint, 'status', 'sent'))), 1,
               'one alert marked as sent');
  perform t_eq(jsonb_array_length(worker_pending_alerts(50)), 1, 'it is not sent twice');
  perform t_as(21);
  perform set_push_enabled(false);
  perform t_eq(jsonb_array_length(worker_pending_alerts(50)), 0,
               'switching alerts off holds back what was queued');
  perform set_push_enabled(true);
  pending := worker_pending_alerts(50);
  perform t_eq(worker_mark_alerts(jsonb_build_array(jsonb_build_object(
                 'id', (pending->0->>'id')::bigint, 'status', 'failed', 'forget_token', true))), 1,
               'a dead token is reported');
  perform t_eq((select count(*)::integer from push_devices where player_id = t_uid(21)), 0,
               'and that phone is forgotten');

  -- An alert nobody sent for half an hour is no longer news.
  update spot_alerts set status = 'queued', created_at = now() - interval '31 minutes'
  where player_id = t_uid(22) and line = 'second';
  perform t_eq(jsonb_array_length(worker_pending_alerts(50)), 0, 'old alerts are left alone');

  -- Registering.
  perform t_as(23);
  perform register_push('token-of-player-22', 'android', 60);
  perform t_eq((select count(*)::integer from push_devices where token = 'token-of-player-22'), 1,
               'a token belongs to one player');
  perform t_eq((select player_id from push_devices where token = 'token-of-player-22'), t_uid(23),
               'the last one to register it');
  perform register_push('token-of-player-23-new', 'android', 99999);
  perform t_eq((select utc_offset_min from push_devices where player_id = t_uid(23)), 840,
               'a wild clock offset is clamped');
  perform t_eq((select count(*)::integer from push_devices where player_id = t_uid(23)), 1,
               'registering again replaces the token');
  failed := false;
  begin
    perform register_push('token-x-12345', 'windows', 0);
  exception when others then
    failed := sqlerrm = 'invalid platform';
  end;
  perform t_eq(failed, true, 'an unknown platform is refused');
  failed := false;
  begin
    perform register_push('short', 'android', 0);
  exception when others then
    failed := sqlerrm = 'invalid token';
  end;
  perform t_eq(failed, true, 'a token that is no token is refused');
end $$;

-- A broken alert check never stops the checker from marking runs.
do $$
declare
  v_id bigint;
begin
  alter table spot_alerts rename column title to title_gone;
  insert into runs (player_id, score, day, played_at, gameplay_version, seed, status)
  values (t_uid(25), 500, spikey_today(), now(), 14, 1, 'pending')
  returning id into v_id;
  update runs set status = 'ok' where id = v_id;
  perform t_eq((select status from runs where id = v_id), 'ok',
               'the run is marked even when alerts fail');
  alter table spot_alerts rename column title_gone to title;
end $$;

-- What each role may do.
do $$
declare
  denied boolean;
begin
  perform t_as(26);
  set local role authenticated;
  perform register_push('token-of-player-26', 'android', 60);
  raise notice 'ok   a signed-in player may register a phone';
  denied := false;
  begin
    perform worker_pending_alerts(10);
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then raise exception 'FAIL the game can read other phones'' tokens'; end if;
  raise notice 'ok   the game cannot read the outbox or tokens';
  denied := false;
  begin
    perform spikey_check_spots(spikey_today());
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then raise exception 'FAIL the game can trigger alerts'; end if;
  raise notice 'ok   the game cannot trigger alerts itself';
  denied := false;
  begin
    perform 1 from push_devices;
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then raise exception 'FAIL the game can read push_devices'; end if;
  raise notice 'ok   the game cannot read the phones table';
  reset role;
  set local role service_role;
  perform worker_pending_alerts(10);
  raise notice 'ok   the sender may read the outbox';
  reset role;
  set local role anon;
  denied := false;
  begin
    perform register_push('token-of-nobody', 'android', 60);
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then raise exception 'FAIL anon can register a phone'; end if;
  raise notice 'ok   a visitor without a session cannot register';
  reset role;
end $$;

select 'ALL DATABASE TESTS PASSED' as result;
