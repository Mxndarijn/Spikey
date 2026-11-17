-- Each run keeps the player's look (flyer, world, trail, portal, music), so a
-- replay can show it exactly as it was played. Looks are cosmetic only: the same
-- seed and taps give the same run whatever the loadout.
-- Also gets replays ready: board rows carry their run's id, and get_run returns
-- what a replay needs (seed, taps, version, loadout).

alter table public.runs add column if not exists loadout jsonb not null default '{}'::jsonb;

-- Replaced with one more argument. The old version goes first so PostgREST never
-- has two submit_run functions to choose from.
drop function if exists public.submit_run(text, text, integer, integer, bigint, jsonb, timestamptz);

create or replace function public.submit_run(
  p_name text,
  p_flyer text,
  p_score integer,
  p_gameplay_version integer,
  p_seed bigint,
  p_taps jsonb,
  p_played_at timestamptz default null,
  p_loadout jsonb default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_at timestamptz := now();
  v_loadout jsonb := '{}'::jsonb;
begin
  perform spikey_ensure_player(p_name, p_flyer);
  if p_played_at is not null
     and p_played_at between now() - interval '2 days' and now() + interval '5 minutes' then
    v_at := p_played_at;
  end if;
  -- Only a small object of names: {"flyer": "dash", "world": "ice", ...}.
  if p_loadout is not null and jsonb_typeof(p_loadout) = 'object'
     and length(p_loadout::text) <= 1024 then
    v_loadout := p_loadout;
  end if;
  insert into runs (player_id, score, day, played_at, gameplay_version, seed, taps, loadout)
  values (
    auth.uid(),
    p_score,
    (v_at at time zone 'Europe/Amsterdam')::date,
    v_at,
    p_gameplay_version,
    p_seed,
    coalesce(p_taps, '[]'::jsonb),
    v_loadout
  );
end
$$;

-- Same board as before, plus each row's best run id ("run") for its replay.
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
    select distinct on (r.player_id) r.player_id, r.score, r.id as run_id
    from runs r
    where p_board = 'all_time' or r.day = v_today
    order by r.player_id, r.score desc, r.played_at asc
  ), ranked as (
    select b.player_id, b.score, b.run_id, p.name, p.flyer,
           rank() over (order by b.score desc) as rank
    from best b
    join players p on p.id = b.player_id
  )
  select jsonb_build_object(
    'entries', coalesce((
      select jsonb_agg(jsonb_build_object(
        'rank', t.rank, 'name', t.name, 'flyer', t.flyer, 'score', t.score,
        'is_me', t.player_id = auth.uid(), 'run', t.run_id
      ) order by t.rank, t.name)
      from (select * from ranked order by rank, name limit 100) t
    ), '[]'::jsonb),
    'me', (
      select jsonb_build_object('rank', rank, 'score', score, 'run', run_id)
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

-- One run, for watching its replay: everyone on the boards can watch everyone.
create or replace function public.get_run(p_run bigint) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'run', r.id, 'name', p.name, 'score', r.score, 'played_at', r.played_at,
    'gameplay_version', r.gameplay_version, 'seed', r.seed, 'taps', r.taps,
    'loadout', r.loadout
  )
  from runs r
  join players p on p.id = r.player_id
  where r.id = p_run and auth.uid() is not null
$$;

revoke all on function public.submit_run(text, text, integer, integer, bigint, jsonb, timestamptz, jsonb)
  from public, anon;
grant execute on function public.submit_run(text, text, integer, integer, bigint, jsonb, timestamptz, jsonb)
  to authenticated;
revoke all on function public.get_run(bigint) from public, anon;
grant execute on function public.get_run(bigint) to authenticated;
