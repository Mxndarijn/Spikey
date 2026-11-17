-- A test notification, for the game's debug screen (Settings, tap the title
-- seven times, Notifications > Send a test notification).
--
-- It goes the same way as a real Board alert: a row in the spot_alerts outbox,
-- then a call to the sender (supabase/functions/send-alerts). So when it
-- arrives, the whole path works: token, server, sender, Firebase, the phone.
-- A player can only send one to their own phone, and one per 30 seconds.
-- Unlike a real alert it ignores the night hours: the tester is awake.

alter table public.spot_alerts drop constraint if exists spot_alerts_line_check;
alter table public.spot_alerts add constraint spot_alerts_line_check
  check (line in ('first', 'second', 'podium', 'top10', 'test'));

-- Returns what happened: 'queued', or why nothing was sent ('no_player',
-- 'no_device', 'off', 'too_soon', 'no_sender').
create or replace function public.send_test_push() returns text
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_enabled boolean;
  v_url text;
  v_secret text;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;
  if not exists (select 1 from players where id = v_uid) then
    return 'no_player';
  end if;
  select enabled into v_enabled from push_devices where player_id = v_uid;
  if not found then
    return 'no_device';
  end if;
  if not v_enabled then
    return 'off';
  end if;
  if exists (
    select 1 from spot_alerts
    where player_id = v_uid and line = 'test' and created_at > now() - interval '30 seconds'
  ) then
    return 'too_soon';
  end if;
  select value into v_url from worker_settings where key = 'push_url';
  select value into v_secret from worker_settings where key = 'push_secret';
  if v_url is null or v_secret is null then
    return 'no_sender';
  end if;
  -- One test row per player: the last one makes room.
  delete from spot_alerts where player_id = v_uid and line = 'test';
  insert into spot_alerts (player_id, day, line, title, body)
  values (v_uid, spikey_today(), 'test', 'Flapjaw test', 'Notifications work on this phone.');
  perform net.http_post(
    url := v_url,
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_secret,
      'Content-Type', 'application/json'
    )
  );
  return 'queued';
end
$$;

revoke all on function public.send_test_push() from public, anon;
grant execute on function public.send_test_push() to authenticated;
