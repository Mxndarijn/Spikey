-- Lost-spot alerts: a push notification when another player's checked run
-- pushes you past a prize line on today's Daily board.
--
--   push_devices   each phone's push token, its clock (minutes ahead of UTC,
--                  for the quiet hours) and the "Board alerts" switch.
--   spot_state     each player's place on today's board when it was last
--                  looked at, to notice a drop.
--   spot_alerts    the alerts, one per player, day and line: an outbox the
--                  sender (a Supabase Edge Function) reads and marks.
--
-- The four lines, each at most once a day per player:
--   first    you were 1st and are not any more          (3 -> 2 diamonds)
--   second   you were 2nd and are 3rd now               (2 -> 2)
--   podium   you were in the top 3 and are not any more (2 or 3 -> 1)
--   top10    you were in the top 10 and are not any more
-- Moves inside 4th to 10th say nothing. The words match game/ui/spot_alert.gd,
-- which shows the same thing as a line on Home.
--
-- An alert that falls in the player's night (22:00 to 08:00 on their phone) is
-- stored as 'quiet' and never sent: by morning the board may be over. A player
-- with no phone registered, or with the switch off, gets 'no_device'.

create table if not exists public.push_devices (
  player_id uuid primary key references auth.users (id) on delete cascade,
  token text not null check (char_length(token) between 8 and 4096),
  platform text not null check (platform in ('android', 'ios')),
  utc_offset_min integer not null default 60 check (utc_offset_min between -720 and 840),
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.spot_state (
  player_id uuid primary key references public.players (id) on delete cascade,
  day date not null,
  place integer not null check (place >= 1)
);

create table if not exists public.spot_alerts (
  id bigint generated always as identity primary key,
  player_id uuid not null references public.players (id) on delete cascade,
  day date not null,
  line text not null check (line in ('first', 'second', 'podium', 'top10')),
  title text not null,
  body text not null,
  status text not null default 'queued'
    check (status in ('queued', 'sent', 'failed', 'quiet', 'no_device')),
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  unique (player_id, day, line)
);

create index if not exists spot_alerts_queued on public.spot_alerts (id) where status = 'queued';

-- No policies: the game can't read or write these tables directly.
alter table public.push_devices enable row level security;
alter table public.spot_state enable row level security;
alter table public.spot_alerts enable row level security;

-- 1 -> '1st', 2 -> '2nd', 11 -> '11th', 23 -> '23rd'.
create or replace function public.spikey_ordinal(p_n integer) returns text
language sql immutable as $$
  select p_n::text || case
    when p_n % 100 between 11 and 13 then 'th'
    when p_n % 10 = 1 then 'st'
    when p_n % 10 = 2 then 'nd'
    when p_n % 10 = 3 then 'rd'
    else 'th'
  end
$$;

create or replace function public.spikey_diamonds_text(p_n integer) returns text
language sql immutable as $$
  select case when p_n = 1 then '1 diamond' else p_n::text || ' diamonds' end
$$;

-- Everyone's place on a day's board, the way prizes are paid: checked runs
-- only, each player's best, the earlier run first on a tie.
create or replace function public.spikey_day_places(p_day date)
returns table (player_id uuid, name text, score integer, place integer)
language sql stable security definer set search_path = public as $$
  select b.player_id, p.name, b.score,
         (row_number() over (order by b.score desc, b.played_at asc, b.run_id asc))::integer
  from (
    select distinct on (r.player_id) r.player_id, r.score, r.played_at, r.id as run_id
    from runs r
    where r.day = p_day and r.status = 'ok'
    order by r.player_id, r.score desc, r.played_at asc
  ) b
  join players p on p.id = b.player_id
$$;

-- Compares today's places with the ones remembered and writes an alert for
-- everyone who dropped past a prize line. Returns how many alerts it queued
-- for sending.
create or replace function public.spikey_check_spots(p_day date) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_drop record;
  v_first record;
  v_second record;
  v_tenth_score integer;
  v_line text;
  v_title text;
  v_body text;
  v_was integer;
  v_now integer;
  v_status text;
  v_hour integer;
  v_device record;
  v_queued integer := 0;
begin
  select t.name, t.score into v_first from spikey_day_places(p_day) t where t.place = 1;
  select t.name, t.score into v_second from spikey_day_places(p_day) t where t.place = 2;
  select t.score into v_tenth_score from spikey_day_places(p_day) t where t.place = 10;
  for v_drop in
    select s.player_id, s.place as old_place, t.place as new_place
    from spot_state s
    join spikey_day_places(p_day) t on t.player_id = s.player_id
    where s.day = p_day and s.place <= 10 and t.place > s.place
  loop
    v_was := spikey_daily_prize(v_drop.old_place);
    v_now := spikey_daily_prize(v_drop.new_place);
    if v_drop.new_place > 10 then
      v_line := 'top10';
      v_title := 'You''re out of the top 10';
      v_body := 'Beat ' || coalesce(v_tenth_score, 0) || ' to win a diamond back.';
    elsif v_drop.old_place <= 3 and v_drop.new_place > 3 then
      v_line := 'podium';
      v_title := 'You''re off the podium';
      v_body := spikey_ordinal(v_drop.new_place) || ' now: ' || spikey_diamonds_text(v_now)
        || ' instead of ' || v_was || '.';
    elsif v_drop.old_place = 1 then
      v_line := 'first';
      v_title := v_first.name || ' took 1st with ' || v_first.score;
      v_body := 'You''re ' || spikey_ordinal(v_drop.new_place) || ' now: '
        || spikey_diamonds_text(v_now) || ' instead of ' || v_was || '.';
    elsif v_drop.old_place = 2 and v_drop.new_place = 3 then
      v_line := 'second';
      v_title := v_second.name || ' passed you with ' || v_second.score;
      v_body := 'You''re 3rd now, still ' || spikey_diamonds_text(v_now) || '.';
    else
      continue;
    end if;
    select d.enabled, d.utc_offset_min into v_device
    from push_devices d where d.player_id = v_drop.player_id;
    if not found or not v_device.enabled then
      v_status := 'no_device';
    else
      v_hour := extract(hour from (now() at time zone 'UTC')
        + make_interval(mins => v_device.utc_offset_min))::integer;
      v_status := case when v_hour >= 22 or v_hour < 8 then 'quiet' else 'queued' end;
    end if;
    insert into spot_alerts (player_id, day, line, title, body, status)
    values (v_drop.player_id, p_day, v_line, v_title, v_body, v_status)
    on conflict (player_id, day, line) do nothing;
    if found and v_status = 'queued' then
      v_queued := v_queued + 1;
    end if;
  end loop;
  -- Remember where everyone stands now: the top 10, and whoever was in it.
  insert into spot_state (player_id, day, place)
  select t.player_id, p_day, t.place
  from spikey_day_places(p_day) t
  where t.place <= 10
     or exists (select 1 from spot_state s where s.player_id = t.player_id and s.day = p_day)
  on conflict (player_id) do update set day = excluded.day, place = excluded.place;
  return v_queued;
end
$$;

-- Runs after the checker marked runs: looks at today's board when one of them
-- passed. A failure here never undoes the checker's work.
create or replace function public.spikey_runs_checked() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_today date := spikey_today();
begin
  if exists (select 1 from changed c where c.status = 'ok' and c.day = v_today) then
    begin
      perform spikey_check_spots(v_today);
    exception when others then
      null;
    end;
  end if;
  return null;
end
$$;

drop trigger if exists runs_check_spots on public.runs;
create trigger runs_check_spots
  after update on public.runs
  referencing new table as changed
  for each statement execute function public.spikey_runs_checked();

-- The game registers this phone for alerts (at every start: tokens and the
-- clock's offset change). p_utc_offset_min: minutes ahead of UTC, 60 for
-- Amsterdam in winter.
create or replace function public.register_push(
  p_token text,
  p_platform text,
  p_utc_offset_min integer default 60
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;
  if p_token is null or char_length(p_token) not between 8 and 4096 then
    raise exception 'invalid token';
  end if;
  if p_platform is null or p_platform not in ('android', 'ios') then
    raise exception 'invalid platform';
  end if;
  -- A token belongs to one phone: a player who signed in again on it takes it over.
  delete from push_devices where token = p_token and player_id <> v_uid;
  insert into push_devices (player_id, token, platform, utc_offset_min)
  values (v_uid, p_token, p_platform, greatest(-720, least(840, coalesce(p_utc_offset_min, 60))))
  on conflict (player_id) do update
  set token = excluded.token, platform = excluded.platform,
      utc_offset_min = excluded.utc_offset_min, updated_at = now();
end
$$;

-- Settings > Board alerts. Does nothing for a phone that never registered.
create or replace function public.set_push_enabled(p_enabled boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  update push_devices
  set enabled = coalesce(p_enabled, true), updated_at = now()
  where player_id = auth.uid();
end
$$;

-- For the sender only: alerts waiting to go out, with the phone to send to.
-- Alerts older than 30 minutes are left alone: they are news no longer.
create or replace function public.worker_pending_alerts(p_limit integer default 100) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', a.id, 'token', d.token, 'platform', d.platform, 'title', a.title, 'body', a.body
  ) order by a.id), '[]'::jsonb)
  from (
    select * from spot_alerts
    where status = 'queued' and created_at > now() - interval '30 minutes'
    order by id
    limit greatest(1, least(coalesce(p_limit, 100), 500))
  ) a
  join push_devices d on d.player_id = a.player_id and d.enabled
$$;

-- For the sender only: [{"id": 12, "status": "sent"}, ...] ('sent' or 'failed').
-- A token the push service no longer knows: {"id": 12, "status": "failed",
-- "forget_token": true} also removes that phone.
create or replace function public.worker_mark_alerts(p_results jsonb) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_count integer;
begin
  delete from push_devices d
  using jsonb_to_recordset(p_results) as x(id bigint, status text, forget_token boolean),
        spot_alerts a
  where a.id = x.id and d.player_id = a.player_id and coalesce(x.forget_token, false);
  update spot_alerts a
  set status = x.status, sent_at = now()
  from jsonb_to_recordset(p_results) as x(id bigint, status text)
  where a.id = x.id and a.status = 'queued' and x.status in ('sent', 'failed');
  get diagnostics v_count = row_count;
  return v_count;
end
$$;

revoke all on function public.spikey_ordinal(integer) from public, anon, authenticated;
revoke all on function public.spikey_diamonds_text(integer) from public, anon, authenticated;
revoke all on function public.spikey_day_places(date) from public, anon, authenticated;
revoke all on function public.spikey_check_spots(date) from public, anon, authenticated;
revoke all on function public.spikey_runs_checked() from public, anon, authenticated;
revoke all on function public.worker_pending_alerts(integer) from public, anon, authenticated;
revoke all on function public.worker_mark_alerts(jsonb) from public, anon, authenticated;
revoke all on function public.register_push(text, text, integer) from public, anon;
revoke all on function public.set_push_enabled(boolean) from public, anon;
grant execute on function public.register_push(text, text, integer) to authenticated;
grant execute on function public.set_push_enabled(boolean) to authenticated;
-- The sender signs in with the project's service key.
grant execute on function public.worker_pending_alerts(integer) to service_role;
grant execute on function public.worker_mark_alerts(jsonb) to service_role;
