-- The database calls the sender when it queued an alert. Any wrong result raises.
-- Runs after 20_test_push.sql and uses its helpers.
\set ON_ERROR_STOP on

delete from runs where day = spikey_today();
delete from spot_alerts;
delete from spot_state;
delete from push_devices;
delete from net.calls;
insert into auth.users (id) select t_uid(n) from generate_series(41, 44) n;
insert into players (id, name) select t_uid(n), 'W' || n from generate_series(41, 44) n;

do $$
begin
  perform t_as(41);
  perform register_push('token-of-player-41', 'android', t_offset_for_hour(12));
  perform t_checked_run(41, 50);

  -- Not set up yet: an alert is queued, nobody is called.
  perform t_checked_run(42, 60);
  perform t_eq((t_alert(41, 'first')).status, 'queued', 'the alert is queued');
  perform t_eq((select count(*)::integer from net.calls), 0, 'no sender set up: no call');

  perform worker_set_push('https://abc.supabase.co/functions/v1/send-alerts', 's3cret');
  -- p41 wins 1st back, p43 takes it: 'first' was used today, so nothing new.
  perform t_checked_run(41, 70);
  perform t_checked_run(43, 80);
  perform t_eq((select count(*)::integer from net.calls), 0, 'nothing queued: no call');
  -- p44 pushes p41 from 2nd to 3rd: a new line, so the sender is called.
  perform t_checked_run(44, 75);
  perform t_eq((t_alert(41, 'second')).status, 'queued', 'a second alert is queued');
  perform t_eq((select count(*)::integer from net.calls), 1, 'the sender is called once');
  perform t_eq((select url from net.calls), 'https://abc.supabase.co/functions/v1/send-alerts',
               'at its address');
  perform t_eq((select headers->>'Authorization' from net.calls), 'Bearer s3cret',
               'with the shared secret');

  perform worker_set_push('', '');
  perform t_eq((select count(*)::integer from worker_settings where key like 'push_%'), 0,
               'an empty secret turns sending off');
  perform worker_set_push('http://plain.example/x', 's3cret');
  perform t_eq((select count(*)::integer from worker_settings where key like 'push_%'), 0,
               'a non-https address is refused');
end $$;

do $$
declare
  denied boolean := false;
begin
  set local role authenticated;
  begin
    perform worker_set_push('https://evil.example/steal', 'x');
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then raise exception 'FAIL the game can redirect the sender'; end if;
  raise notice 'ok   the game cannot change where alerts are sent';
  reset role;
end $$;

select 'ALL DATABASE TESTS PASSED' as result;
