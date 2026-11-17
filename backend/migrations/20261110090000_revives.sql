-- Revives (gameplay version 15, docs/REVIVE.md). A run can be revived once;
-- the tick it happened at is part of the replay, so the checker replays it
-- like a tap. A revived run counts on the boards and is marked "revived".
--
-- Deploy this before phones that can revive: without the p_revives argument a
-- revived run can't be stored, and such phones keep the run until it can.

alter table public.runs
  add column if not exists revives jsonb not null default '[]'::jsonb;

-- Replaced with one more argument (the revive ticks). The old one goes first
-- so PostgREST never has two submit_run functions to choose from. Phones that
-- don't send it still work: it defaults to no revives.
drop function if exists public.submit_run(
  text, text, integer, integer, bigint, jsonb, timestamptz, jsonb, integer, integer, integer
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
  p_end_tick integer default null,
  p_revives jsonb default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_at timestamptz := now();
  v_loadout jsonb := '{}'::jsonb;
  v_taps jsonb := coalesce(p_taps, '[]'::jsonb);
  v_revives jsonb := coalesce(p_revives, '[]'::jsonb);
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
  -- One revive per run (SimConfig.MAX_REVIVES).
  if jsonb_typeof(v_revives) <> 'array' or jsonb_array_length(v_revives) > 1 then
    raise exception 'invalid revives';
  end if;
  insert into runs (
    player_id, score, day, played_at, gameplay_version, seed, taps, loadout,
    season, coins, end_tick, revives
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
    case when p_end_tick between 0 and 10000000 then p_end_tick end,
    v_revives
  );
end
$$;

-- The boards as before; each row now says whether its run used a revive.
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
           r.status = 'ok' as verified,
           jsonb_array_length(r.revives) > 0 as revived
    from runs r
    where (p_board = 'all_time' or r.day = v_today)
      and (r.status = 'ok' or (r.status = 'pending' and r.player_id = auth.uid()))
    order by r.player_id, r.score desc, r.played_at asc
  ), ranked as (
    select b.player_id, b.score, b.run_id, b.verified, b.revived, p.name, p.flyer,
           rank() over (order by b.score desc) as rank
    from best b
    join players p on p.id = b.player_id
  )
  select jsonb_build_object(
    'entries', coalesce((
      select jsonb_agg(jsonb_build_object(
        'rank', t.rank, 'name', t.name, 'flyer', t.flyer, 'score', t.score,
        'is_me', t.player_id = auth.uid(), 'run', t.run_id, 'verified', t.verified,
        'revived', t.revived
      ) order by t.rank, t.name)
      from (select * from ranked order by rank, name limit 100) t
    ), '[]'::jsonb),
    'me', (
      select jsonb_build_object(
        'rank', rank, 'score', score, 'run', run_id, 'verified', verified, 'revived', revived
      )
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

-- One run for its replay, now with its revive ticks.
create or replace function public.get_run(p_run bigint) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'run', r.id, 'name', p.name, 'score', r.score, 'played_at', r.played_at,
    'gameplay_version', r.gameplay_version, 'seed', r.seed, 'taps', r.taps,
    'loadout', r.loadout, 'season', r.season, 'revives', r.revives
  )
  from runs r
  join players p on p.id = r.player_id
  where r.id = p_run and auth.uid() is not null
    and (r.status = 'ok' or r.player_id = auth.uid())
$$;

-- For the checker only: the oldest runs that wait to be checked, with their
-- revive ticks.
create or replace function public.worker_pending_runs(p_limit integer default 500) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r.id, 'gameplay_version', r.gameplay_version, 'seed', r.seed,
    'season', r.season, 'taps', r.taps, 'revives', r.revives, 'score', r.score,
    'coins', r.coins, 'end_tick', r.end_tick, 'day', r.day
  ) order by r.id), '[]'::jsonb)
  from (
    select * from runs
    where status = 'pending'
    order by id
    limit greatest(1, least(coalesce(p_limit, 500), 2000))
  ) r
$$;

revoke all on function public.submit_run(
  text, text, integer, integer, bigint, jsonb, timestamptz, jsonb, integer, integer, integer, jsonb
) from public, anon;
grant execute on function public.submit_run(
  text, text, integer, integer, bigint, jsonb, timestamptz, jsonb, integer, integer, integer, jsonb
) to authenticated;
revoke all on function public.get_run(bigint) from public, anon;
grant execute on function public.get_run(bigint) to authenticated;
revoke all on function public.worker_pending_runs(integer) from public, anon, authenticated;
