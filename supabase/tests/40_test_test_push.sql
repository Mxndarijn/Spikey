-- The debug screen's test notification. Any wrong result raises.
\set ON_ERROR_STOP on

insert into auth.users (id) select t_uid(n) from generate_series(41, 44) n;
insert into players (id, name) select t_uid(n), 'T' || n from generate_series(41, 43) n;

do $$
declare
  v_calls integer;
begin
  perform worker_set_push('https://sender.example/send-alerts', 's3cret');
  select count(*) into v_calls from net.calls;

  perform t_as(44);
  perform t_eq(send_test_push(), 'no_player', 'no test without a player');
  perform t_as(41);
  perform t_eq(send_test_push(), 'no_device', 'no test without a registered phone');

  perform register_push('token-of-player-41', 'ios', 60);
  perform set_push_enabled(false);
  perform t_eq(send_test_push(), 'off', 'no test while alerts are off');
  perform set_push_enabled(true);

  perform t_eq(send_test_push(), 'queued', 'a test is queued');
  perform t_eq((select count(*)::integer from spot_alerts
                where player_id = t_uid(41) and line = 'test' and status = 'queued'), 1,
               'it waits in the outbox');
  perform t_eq((select count(*)::integer from net.calls), v_calls + 1, 'the sender is called');
  perform t_eq((select count(*)::integer from jsonb_array_elements(worker_pending_alerts(500)) a
                where a->>'token' = 'token-of-player-41' and a->>'title' = 'Flapjaw test'), 1,
               'the sender finds it, with this phone''s token');

  perform t_eq(send_test_push(), 'too_soon', 'not twice within half a minute');
  update spot_alerts set created_at = now() - interval '1 minute', status = 'sent'
  where player_id = t_uid(41) and line = 'test';
  perform t_eq(send_test_push(), 'queued', 'again after half a minute');
  perform t_eq((select count(*)::integer from spot_alerts
                where player_id = t_uid(41) and line = 'test'), 1,
               'one test row per player');

  perform t_as(42);
  perform register_push('token-of-player-42', 'android', 60);
  perform worker_set_push('', '');
  perform t_eq(send_test_push(), 'no_sender', 'no test without a sender');
  perform t_eq((select count(*)::integer from spot_alerts
                where player_id = t_uid(42) and line = 'test'), 0,
               'nothing is queued without a sender');
end $$;

do $$
declare
  denied boolean := false;
begin
  perform set_config('request.jwt.claim.sub', '', false);
  set local role anon;
  begin
    perform send_test_push();
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then raise exception 'FAIL a player who is not signed in can send a test'; end if;
  raise notice 'ok   only signed-in players can send a test';
  reset role;
end $$;

select 'ALL DATABASE TESTS PASSED' as result;
