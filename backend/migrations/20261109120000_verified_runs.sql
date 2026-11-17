-- Verified leaderboards. Every run is replayed by a checker
-- (.github/workflows/verify-runs.yml running server/verify_batch.gd) with the
-- same sim/ code the phones use. Same score, coins and end tick: the run is
-- "ok" and counts on the boards. Anything else is "rejected" and never shows.
--
-- Status of a run:
--   pending   just sent, not checked yet. Counts only on its own player's view
--             of the boards, so a new best shows at once on that phone.
--   ok        replayed and matches: on the boards for everyone.
--   rejected  replay does not match (fake or broken run). Never shown.
--   outdated  played on an older gameplay version than the checker knows.
--             Never shown; the player needs to update the app.
--
-- Runs from before this file start as pending, so the checker also goes over
-- them once. They have no season, coins or end tick stored: the checker takes
-- the season from the date they were played and only checks the score.

alter table public.runs
  add column if not exists season integer,
  add column if not exists coins integer,
  add column if not exists end_tick integer,
  add column if not exists status text not null default 'pending',
  add column if not exists reason text not null default '',
  add column if not exists checked_at timestamptz;

do $$
begin
  alter table public.runs add constraint runs_status_check
    check (status in ('pending', 'ok', 'rejected', 'outdated'));
exception when duplicate_object then null;
end
$$;

create index if not exists runs_pending on public.runs (id) where status = 'pending';

-- Replaced with three more arguments (season, coins, end tick). The old one
-- goes first so PostgREST never has two submit_run functions to choose from.
-- Phones that don't send the new arguments still work: they default to null.
drop function if exists public.submit_run(
  text, text, integer, integer, bigint, jsonb, timestamptz, jsonb
);

create or replace function public.submit_run(
  p_name text,
  p_flyer text,
  p_score integer,
  p_gameplay_version integer,
  p_seed bigint,
  p_taps jsonb,
  p_played_at timestamptz default null,
  p_loadout jsonb default null,
  p_season integer default null,
  p_coins integer default null,
  p_end_tick integer default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_at timestamptz := now();
  v_loadout jsonb := '{}'::jsonb;
  v_taps jsonb := coalesce(p_taps, '[]'::jsonb);
begin
  perform spikey_ensure_player(p_name, p_flyer);
  if p_played_at is not null
     and p_played_at between now() - interval '2 days' and now() + interval '5 minutes' then
    v_at := p_played_at;
  end if;
  if p_loadout is not null and jsonb_typeof(p_loadout) = 'object'
     and length(p_loadout::text) <= 1024 then
    v_loadout := p_loadout;
  end if;
  -- 30 minutes of play (the sim's cap) never needs more taps than this.
  if jsonb_typeof(v_taps) <> 'array' or jsonb_array_length(v_taps) > 20000 then
    raise exception 'invalid taps';
  end if;
  insert into runs (
    player_id, score, day, played_at, gameplay_version, seed, taps, loadout,
    season, coins, end_tick
  )
  values (
    auth.uid(),
    p_score,
    (v_at at time zone 'Europe/Amsterdam')::date,
    v_at,
    p_gameplay_version,
    p_seed,
    v_taps,
    v_loadout,
    -- Seasons.NONE is -1.
    case when p_season between -1 and 100 then p_season end,
    case when p_coins between 0 and 100000 then p_coins end,
    case when p_end_tick between 0 and 10000000 then p_end_tick end
  );
end
$$;

-- Same boards as before, with only checked runs (plus the caller's own runs
-- that wait for the checker). Each row says whether its run was checked.
create or replace function public.get_board(p_board text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_today date := spikey_today();
  v_result jsonb;
begin
  if p_board not in ('daily', 'all_time') then
    raise exception 'unknown board %', p_board;
  end if;
  with best as (
    select distinct on (r.player_id) r.player_id, r.score, r.id as run_id,
           r.status = 'ok' as verified
    from runs r
    where (p_board = 'all_time' or r.day = v_today)
      and (r.status = 'ok' or (r.status = 'pending' and r.player_id = auth.uid()))
    order by r.player_id, r.score desc, r.played_at asc
  ), ranked as (
    select b.player_id, b.score, b.run_id, b.verified, p.name, p.flyer,
           rank() over (order by b.score desc) as rank
    from best b
    join players p on p.id = b.player_id
  )
  select jsonb_build_object(
    'entries', coalesce((
      select jsonb_agg(jsonb_build_object(
        'rank', t.rank, 'name', t.name, 'flyer', t.flyer, 'score', t.score,
        'is_me', t.player_id = auth.uid(), 'run', t.run_id, 'verified', t.verified
      ) order by t.rank, t.name)
      from (select * from ranked order by rank, name limit 100) t
    ), '[]'::jsonb),
    'me', (
      select jsonb_build_object('rank', rank, 'score', score, 'run', run_id, 'verified', verified)
      from ranked where player_id = auth.uid()
    ),
    'players', (select count(*) from ranked),
    'resets_in_s', case
      when p_board = 'daily' then extract(epoch from spikey_next_midnight() - now())::integer
      else -1
    end
  ) into v_result;
  return v_result;
end
$$;

-- One run for its replay, now with its season (seasonal rooms replay as they
-- were played). Rejected runs can't be watched, except by their own player.
create or replace function public.get_run(p_run bigint) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'run', r.id, 'name', p.name, 'score', r.score, 'played_at', r.played_at,
    'gameplay_version', r.gameplay_version, 'seed', r.seed, 'taps', r.taps,
    'loadout', r.loadout, 'season', r.season
  )
  from runs r
  join players p on p.id = r.player_id
  where r.id = p_run and auth.uid() is not null
    and (r.status = 'ok' or r.player_id = auth.uid())
$$;

-- For the checker only (it connects as the database owner): the oldest runs
-- that wait to be checked.
create or replace function public.worker_pending_runs(p_limit integer default 500) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r.id, 'gameplay_version', r.gameplay_version, 'seed', r.seed,
    'season', r.season, 'taps', r.taps, 'score', r.score, 'coins', r.coins,
    'end_tick', r.end_tick, 'day', r.day
  ) order by r.id), '[]'::jsonb)
  from (
    select * from runs
    where status = 'pending'
    order by id
    limit greatest(1, least(coalesce(p_limit, 500), 2000))
  ) r
$$;

-- For the checker only: [{"id", "status", "reason"}, ...]. Only pending runs
-- change, so a run is never checked twice. Returns how many runs changed.
create or replace function public.worker_record_results(p_results jsonb) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_count integer;
begin
  update runs r
  set status = x.status,
      reason = left(coalesce(x.reason, ''), 200),
      verified = x.status = 'ok',
      checked_at = now()
  from jsonb_to_recordset(p_results) as x(id bigint, status text, reason text)
  where r.id = x.id
    and r.status = 'pending'
    and x.status in ('ok', 'rejected', 'outdated');
  get diagnostics v_count = row_count;
  return v_count;
end
$$;

revoke all on function public.submit_run(
  text, text, integer, integer, bigint, jsonb, timestamptz, jsonb, integer, integer, integer
) from public, anon;
grant execute on function public.submit_run(
  text, text, integer, integer, bigint, jsonb, timestamptz, jsonb, integer, integer, integer
) to authenticated;
revoke all on function public.get_run(bigint) from public, anon;
grant execute on function public.get_run(bigint) to authenticated;
revoke all on function public.worker_pending_runs(integer) from public, anon, authenticated;
revoke all on function public.worker_record_results(jsonb) from public, anon, authenticated;
