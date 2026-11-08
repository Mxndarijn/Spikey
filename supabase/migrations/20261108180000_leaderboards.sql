-- Spikey leaderboards, friends version (Supabase free plan).
-- Applied by .github/workflows/supabase-db.yml (supabase db push) when this folder
-- changes on main. It can also be pasted into the SQL Editor by hand: running it
-- again is safe, it only creates what is missing and replaces the functions.
-- Later changes go in a NEW file in supabase/migrations/, never edit this one
-- after it has been applied.
--
-- Boards: "daily" (best run per player today, resets at local midnight) and
-- "all_time" (best run per player ever). Runs are stored with their seed and
-- taps but are NOT verified yet: anyone with the app's public key could post a
-- fake score. Fine among friends; a verification server can check them later.
--
-- The tables are locked (row level security on, no policies). The game can only
-- use the functions at the bottom, and only as a signed-in (anonymous) player.

-- The day boundary for the daily board. Change the time zone to yours.
create or replace function public.spikey_today() returns date
language sql stable as $$
  select (now() at time zone 'Europe/Amsterdam')::date
$$;

create or replace function public.spikey_next_midnight() returns timestamptz
language sql stable as $$
  select (public.spikey_today() + 1)::timestamp at time zone 'Europe/Amsterdam'
$$;

create table if not exists public.players (
  id uuid primary key references auth.users (id) on delete cascade,
  name text not null check (name ~ '^[A-Za-z0-9._]{3,14}$'),
  flyer text not null default 'buzz' check (char_length(flyer) between 1 and 32),
  updated_at timestamptz not null default now()
);

create table if not exists public.runs (
  id bigint generated always as identity primary key,
  player_id uuid not null references public.players (id) on delete cascade,
  score integer not null check (score between 0 and 100000),
  day date not null,
  played_at timestamptz not null default now(),
  gameplay_version integer not null,
  seed bigint not null,
  taps jsonb not null default '[]'::jsonb,
  verified boolean not null default false
);

create index if not exists runs_day_score on public.runs (day, score desc);
create index if not exists runs_player_score on public.runs (player_id, score desc);

alter table public.players enable row level security;
alter table public.runs enable row level security;

-- Makes sure the caller has a players row; keeps an existing name when p_name is empty.
create or replace function public.spikey_ensure_player(p_name text, p_flyer text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_flyer text := coalesce(nullif(left(coalesce(p_flyer, ''), 32), ''), 'buzz');
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  if v_name is not null and v_name !~ '^[A-Za-z0-9._]{3,14}$' then
    raise exception 'invalid name';
  end if;
  insert into players (id, name, flyer)
  values (auth.uid(), coalesce(v_name, 'Flyer' || left(md5(auth.uid()::text), 4)), v_flyer)
  on conflict (id) do update
    set name = coalesce(v_name, players.name),
        flyer = excluded.flyer,
        updated_at = now();
end
$$;

-- The player's leaderboard name and flyer.
create or replace function public.set_player(p_name text, p_flyer text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform spikey_ensure_player(p_name, p_flyer);
end
$$;

-- A finished real run. p_played_at lets runs played offline count on the day
-- they were played (only if that was within the last two days).
create or replace function public.submit_run(
  p_name text,
  p_flyer text,
  p_score integer,
  p_gameplay_version integer,
  p_seed bigint,
  p_taps jsonb,
  p_played_at timestamptz default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_at timestamptz := now();
begin
  perform spikey_ensure_player(p_name, p_flyer);
  if p_played_at is not null
     and p_played_at between now() - interval '2 days' and now() + interval '5 minutes' then
    v_at := p_played_at;
  end if;
  insert into runs (player_id, score, day, played_at, gameplay_version, seed, taps)
  values (
    auth.uid(),
    p_score,
    (v_at at time zone 'Europe/Amsterdam')::date,
    v_at,
    p_gameplay_version,
    p_seed,
    coalesce(p_taps, '[]'::jsonb)
  );
end
$$;

-- One board: the top 100 (best run per player), the caller's own rank, how
-- many players are on it, and for the daily board the seconds until it resets.
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
    select r.player_id, max(r.score) as score
    from runs r
    where p_board = 'all_time' or r.day = v_today
    group by r.player_id
  ), ranked as (
    select b.player_id, b.score, p.name, p.flyer,
           rank() over (order by b.score desc) as rank
    from best b
    join players p on p.id = b.player_id
  )
  select jsonb_build_object(
    'entries', coalesce((
      select jsonb_agg(jsonb_build_object(
        'rank', t.rank, 'name', t.name, 'flyer', t.flyer, 'score', t.score,
        'is_me', t.player_id = auth.uid()
      ) order by t.rank, t.name)
      from (select * from ranked order by rank, name limit 100) t
    ), '[]'::jsonb),
    'me', (
      select jsonb_build_object('rank', rank, 'score', score)
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

-- For the weekly keep-awake job (.github/workflows/supabase-keepalive.yml).
create or replace function public.ping() returns integer
language sql stable as $$ select 1 $$;

revoke all on function public.spikey_ensure_player(text, text) from public, anon, authenticated;
revoke all on function public.set_player(text, text) from public, anon;
revoke all on function public.submit_run(text, text, integer, integer, bigint, jsonb, timestamptz)
  from public, anon;
revoke all on function public.get_board(text) from public, anon;
grant execute on function public.set_player(text, text) to authenticated;
grant execute on function public.submit_run(text, text, integer, integer, bigint, jsonb, timestamptz)
  to authenticated;
grant execute on function public.get_board(text) to authenticated;
grant execute on function public.ping() to anon, authenticated;
