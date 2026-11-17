-- Daily Run: one map a day, the same for every player, with its own board.
--
--   daily_runs         one row per day: its number (No. 1 is the first day),
--                      the seed and the season. Made by the first call of the
--                      day; the seed comes from a secret, so nobody can play
--                      tomorrow's map early.
--   daily_tries        every try a player started: DAILY_RUN_TRIES a day (3),
--                      each one started online, each one sent once.
--   daily_run_prizes   who finished in the top 10 of a finished day's Daily
--                      Run, and whether the prize was claimed.
--   daily_run_settled  days whose Daily Run prizes were handed out.
--   runs.board         'endless' (every run so far: the Today and All-time
--                      boards) or 'daily_run'. A Daily Run run counts only on
--                      the Daily Run board. It still counts, like any checked
--                      run, for the best-score milestones, the 7-day streak
--                      and the gold ceiling.
--
-- One clock for both daily boards (spikey_board_zone, below): Today and the
-- Daily Run both reset at midnight Europe/Amsterdam, so players see one reset.
-- To move both, change that one function.
--
-- Prizes: spikey_daily_run_prize (below) pays the same tiers as Today's board
-- (3, 2, 2, then 1 for 4th to 10th: 14 more diamonds a day, 28 in all). To
-- change it, change that one function and Economy.DAILY_RUN_PRIZES.
--
-- Replays of a Daily Run stay locked until its day is over (get_run and the
-- board hide them), so nobody copies the leader's line on today's map.
--
-- No revives: a crash ends the try (submit_daily_run stores none). The
-- checker (server/run_checker.gd) checks these runs like any other; the seed
-- and season are checked here, against the day's row, when the run arrives.
--
-- This runs after 20261113120000_reset_boards.sql, which deleted every run
-- when it was applied: Daily Run's tables start empty and are not touched by
-- it. A later spikey_reset_boards() call deletes runs of both boards; a try
-- keeps its submitted_at, so it can't be sent again.

-- The one clock for the daily boards.
create or replace function public.spikey_board_zone() returns text
language sql immutable as $$
  select 'Europe/Amsterdam'
$$;

create or replace function public.spikey_today() returns date
language sql stable as $$
  select (now() at time zone public.spikey_board_zone())::date
$$;

create or replace function public.spikey_next_midnight() returns timestamptz
language sql stable as $$
  select (public.spikey_today() + 1)::timestamp at time zone public.spikey_board_zone()
$$;

-- Tries a day (DailyRunRules.TRIES_PER_DAY holds the same number).
create or replace function public.spikey_daily_run_tries() returns integer
language sql immutable as $$
  select 3
$$;

-- The first Daily Run's day: it is No. 1.
create or replace function public.spikey_daily_run_epoch() returns date
language sql immutable as $$
  select date '2026-11-14'
$$;

-- Diamonds for a place on a finished Daily Run (Economy.DAILY_RUN_PRIZES).
create or replace function public.spikey_daily_run_prize(p_rank integer) returns integer
language sql immutable as $$
  select public.spikey_daily_prize(p_rank)
$$;

-- The season of a date, as SeasonCalendar.for_date (meta/season_calendar.gd):
-- Seasons.HALLOWEEN 0, WINTER 1, VALENTINE 2, SPRING 3, SUMMER 4, NEW_YEAR 5,
-- NONE -1. Every player of a day's Daily Run plays it in this season.
create or replace function public.spikey_season_of(p_day date) returns integer
language sql immutable as $$
  select case
    when extract(month from p_day) = 10 then 0
    when extract(month from p_day) = 12 then 1
    when extract(month from p_day) = 1 and extract(day from p_day) <= 7 then 5
    when extract(month from p_day) = 2 and extract(day from p_day) <= 14 then 2
    when extract(month from p_day) in (3, 4) then 3
    when extract(month from p_day) in (7, 8) then 4
    else -1
  end
$$;

alter table public.runs add column if not exists board text not null default 'endless';
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'runs_board_check') then
    alter table public.runs add constraint runs_board_check
      check (board in ('endless', 'daily_run'));
  end if;
end $$;
create index if not exists runs_board_day on public.runs (board, day, score desc);

create table if not exists public.daily_run_secret (
  id integer primary key default 1 check (id = 1),
  secret text not null
);
insert into public.daily_run_secret (id, secret)
values (1, gen_random_uuid()::text || gen_random_uuid()::text)
on conflict (id) do nothing;

create table if not exists public.daily_runs (
  day date primary key,
  number integer not null,
  seed bigint not null check (seed between 0 and 4294967295),
  season integer not null,
  created_at timestamptz not null default now()
);

create table if not exists public.daily_tries (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.players (id) on delete cascade,
  day date not null references public.daily_runs (day),
  n integer not null check (n >= 1),
  started_at timestamptz not null default now(),
  submitted_at timestamptz,
  run_id bigint references public.runs (id) on delete set null,
  unique (player_id, day, n)
);

create table if not exists public.daily_run_prizes (
  day date not null,
  player_id uuid not null references public.players (id) on delete cascade,
  rank integer not null check (rank between 1 and 10),
  score integer not null,
  diamonds integer not null check (diamonds > 0),
  claimed_at timestamptz,
  primary key (day, player_id)
);

create index if not exists daily_run_prizes_unclaimed on public.daily_run_prizes (player_id)
  where claimed_at is null;

create table if not exists public.daily_run_settled (
  day date primary key,
  settled_at timestamptz not null default now()
);

-- No policies: the game can't read or write these tables directly.
alter table public.daily_run_secret enable row level security;
alter table public.daily_runs enable row level security;
alter table public.daily_tries enable row level security;
alter table public.daily_run_prizes enable row level security;
alter table public.daily_run_settled enable row level security;

alter table public.diamond_ledger drop constraint if exists diamond_ledger_reason_check;
alter table public.diamond_ledger add constraint diamond_ledger_reason_check check (
  reason in ('daily_prize', 'daily_run_prize', 'milestone', 'streak', 'pack', 'convert', 'item')
);

-- A day's Daily Run, made the first time anyone asks for it.
create or replace function public.spikey_daily_run_of(p_day date) returns public.daily_runs
language plpgsql security definer set search_path = public as $$
declare
  v_row daily_runs;
begin
  select * into v_row from daily_runs where day = p_day;
  if found then
    return v_row;
  end if;
  insert into daily_runs (day, number, seed, season)
  select p_day,
         (p_day - spikey_daily_run_epoch()) + 1,
         ('x' || substr(md5(s.secret || ':' || p_day::text), 1, 8))::bit(32)::bigint,
         spikey_season_of(p_day)
  from daily_run_secret s
  where s.id = 1
  on conflict (day) do nothing;
  select * into v_row from daily_runs where day = p_day;
  return v_row;
end
$$;

-- Everyone's place on a day's Daily Run, the way prizes are paid: checked runs
-- only, each player's best, the earlier run first on a tie.
create or replace function public.spikey_daily_run_places(p_day date)
returns table (player_id uuid, name text, flyer text, score integer, place integer, run_id bigint)
language sql stable security definer set search_path = public as $$
  select b.player_id, p.name, p.flyer, b.score,
         (row_number() over (order by b.score desc, b.played_at asc, b.run_id asc))::integer,
         b.run_id
  from (
    select distinct on (r.player_id) r.player_id, r.score, r.played_at, r.id as run_id
    from runs r
    where r.board = 'daily_run' and r.day = p_day and r.status = 'ok'
    order by r.player_id, r.score desc, r.played_at asc, r.id asc
  ) b
  join players p on p.id = b.player_id
$$;

-- Pays the finished Daily Runs of the last 7 days, the same way as Today's
-- board (spikey_settle_days): yesterday waits while one of its runs waits for
-- the checker; each day pays once.
create or replace function public.spikey_settle_daily_runs() returns void
language plpgsql security definer set search_path = public as $$
declare
  v_today date := spikey_today();
  v_day date;
begin
  for v_day in
    select distinct r.day
    from runs r
    where r.board = 'daily_run'
      and r.day < v_today
      and r.day >= v_today - 7
      and not exists (select 1 from daily_run_settled s where s.day = r.day)
    order by r.day
  loop
    if v_day >= v_today - 1
       and exists (
         select 1 from runs r
         where r.board = 'daily_run' and r.day = v_day and r.status = 'pending'
       ) then
      continue;
    end if;
    insert into daily_run_settled (day) values (v_day) on conflict (day) do nothing;
    if not found then
      continue;
    end if;
    insert into daily_run_prizes (day, player_id, rank, score, diamonds)
    select v_day, t.player_id, t.place, t.score, spikey_daily_run_prize(t.place)
    from spikey_daily_run_places(v_day) t
    where t.place <= 10 and spikey_daily_run_prize(t.place) > 0
    on conflict (day, player_id) do nothing;
  end loop;
end
$$;

-- As before (20261110100000_diamonds.sql), for Today's board only (endless
-- runs), and then the Daily Runs.
create or replace function public.spikey_settle_days() returns void
language plpgsql security definer set search_path = public as $$
declare
  v_today date := spikey_today();
  v_day date;
begin
  for v_day in
    select distinct r.day
    from runs r
    where r.board = 'endless'
      and r.day < v_today
      and r.day >= v_today - 7
      and not exists (select 1 from settled_days s where s.day = r.day)
    order by r.day
  loop
    if v_day >= v_today - 1
       and exists (
         select 1 from runs r
         where r.board = 'endless' and r.day = v_day and r.status = 'pending'
       ) then
      continue;
    end if;
    insert into settled_days (day) values (v_day) on conflict (day) do nothing;
    if not found then
      continue;
    end if;
    insert into daily_prizes (day, player_id, rank, score, diamonds)
    select v_day, t.player_id, t.place, t.score, spikey_daily_prize(t.place)
    from (
      select b.player_id, b.score,
             (row_number() over (order by b.score desc, b.played_at asc, b.run_id asc))::integer
               as place
      from (
        select distinct on (r.player_id) r.player_id, r.score, r.played_at, r.id as run_id
        from runs r
        where r.board = 'endless' and r.day = v_day and r.status = 'ok'
        order by r.player_id, r.score desc, r.played_at asc
      ) b
    ) t
    where t.place <= 10
    on conflict (day, player_id) do nothing;
  end loop;
  perform spikey_settle_daily_runs();
end
$$;

-- As before (20261110110000_push_alerts.sql), Today's board only: the lost-spot
-- alerts speak of Today's prizes.
create or replace function public.spikey_day_places(p_day date)
returns table (player_id uuid, name text, score integer, place integer)
language sql stable security definer set search_path = public as $$
  select b.player_id, p.name, b.score,
         (row_number() over (order by b.score desc, b.played_at asc, b.run_id asc))::integer
  from (
    select distinct on (r.player_id) r.player_id, r.score, r.played_at, r.id as run_id
    from runs r
    where r.board = 'endless' and r.day = p_day and r.status = 'ok'
    order by r.player_id, r.score desc, r.played_at asc
  ) b
  join players p on p.id = b.player_id
$$;

-- As before (20261110090000_revives.sql), with the day on the one clock.
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
  if jsonb_typeof(v_taps) <> 'array' or jsonb_array_length(v_taps) > 20000 then
    raise exception 'invalid taps';
  end if;
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
    (v_at at time zone spikey_board_zone())::date,
    v_at,
    p_gameplay_version,
    p_seed,
    v_taps,
    v_loadout,
    case when p_season between -1 and 100 then p_season end,
    case when p_coins between 0 and 100000 then p_coins end,
    case when p_end_tick between 0 and 10000000 then p_end_tick end,
    v_revives
  );
end
$$;

-- Today's Daily Run for the caller:
-- {"day": "2026-11-14", "number": 1, "season": -1, "resets_in_s": 3600,
--  "tries_max": 3, "tries_used": 1, "best": 31, "rank": 12, "players": 2140,
--  "yesterday": {"day", "number", "players", "settled",
--                "me": {"rank", "score"} or null,
--                "top": [{"rank", "name", "flyer", "score", "run"}, ...3]} or null}
-- The seed is not in it: it comes with a try (start_daily_try).
create or replace function public.get_daily_run() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_today date := spikey_today();
  v_row daily_runs;
  v_yday daily_runs;
  v_yesterday jsonb;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;
  v_row := spikey_daily_run_of(v_today);
  select * into v_yday from daily_runs where day = v_today - 1;
  if found then
    v_yesterday := jsonb_build_object(
      'day', v_yday.day,
      'number', v_yday.number,
      'players', (select count(*) from spikey_daily_run_places(v_yday.day)),
      'settled', exists (select 1 from daily_run_settled s where s.day = v_yday.day),
      'me', (
        select jsonb_build_object('rank', t.place, 'score', t.score)
        from spikey_daily_run_places(v_yday.day) t where t.player_id = v_uid
      ),
      'top', coalesce((
        select jsonb_agg(jsonb_build_object(
          'rank', t.place, 'name', t.name, 'flyer', t.flyer, 'score', t.score, 'run', t.run_id
        ) order by t.place)
        from spikey_daily_run_places(v_yday.day) t where t.place <= 3
      ), '[]'::jsonb)
    );
  end if;
  return jsonb_build_object(
    'day', v_row.day,
    'number', v_row.number,
    'season', v_row.season,
    'resets_in_s', extract(epoch from spikey_next_midnight() - now())::integer,
    'tries_max', spikey_daily_run_tries(),
    'tries_used', (
      select count(*)::integer from daily_tries t where t.player_id = v_uid and t.day = v_today
    ),
    'best', (
      select max(r.score) from runs r
      where r.board = 'daily_run' and r.day = v_today and r.player_id = v_uid
        and r.status in ('ok', 'pending')
    ),
    'rank', (
      select b.rank from (
        select x.player_id, rank() over (order by x.score desc) as rank
        from (
          select r.player_id, max(r.score) as score from runs r
          where r.board = 'daily_run' and r.day = v_today
            and (r.status = 'ok' or (r.status = 'pending' and r.player_id = v_uid))
          group by r.player_id
        ) x
      ) b where b.player_id = v_uid
    ),
    'players', (
      select count(distinct r.player_id)::integer from runs r
      where r.board = 'daily_run' and r.day = v_today
        and (r.status = 'ok' or (r.status = 'pending' and r.player_id = v_uid))
    ),
    'yesterday', v_yesterday
  );
end
$$;

-- Starts the caller's next try on today's map: {"try": uuid, "n": 2,
-- "tries_max": 3, "seed", "season", "day", "number"}. Raises 'no tries left'
-- after the last one.
create or replace function public.start_daily_try(p_name text, p_flyer text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_today date := spikey_today();
  v_row daily_runs;
  v_used integer;
  v_id uuid;
begin
  perform spikey_ensure_player(p_name, p_flyer);
  v_row := spikey_daily_run_of(v_today);
  select count(*)::integer into v_used
  from daily_tries t where t.player_id = v_uid and t.day = v_today;
  if v_used >= spikey_daily_run_tries() then
    raise exception 'no tries left';
  end if;
  insert into daily_tries (player_id, day, n) values (v_uid, v_today, v_used + 1)
  returning id into v_id;
  return jsonb_build_object(
    'try', v_id, 'n', v_used + 1, 'tries_max', spikey_daily_run_tries(),
    'seed', v_row.seed, 'season', v_row.season, 'day', v_row.day, 'number', v_row.number
  );
end
$$;

-- A finished try. Its run counts on the day the try started, even when it
-- arrives after midnight (sent from the queue later); one that arrives after
-- that day was paid wins nothing. Raises when the try isn't the caller's, was
-- sent before, is older than 2 days, or doesn't play that day's map.
create or replace function public.submit_daily_run(
  p_try uuid,
  p_name text,
  p_flyer text,
  p_score integer,
  p_gameplay_version integer,
  p_seed bigint,
  p_taps jsonb,
  p_loadout jsonb default null,
  p_season integer default null,
  p_coins integer default null,
  p_end_tick integer default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_try daily_tries;
  v_row daily_runs;
  v_loadout jsonb := '{}'::jsonb;
  v_taps jsonb := coalesce(p_taps, '[]'::jsonb);
  v_run bigint;
begin
  perform spikey_ensure_player(p_name, p_flyer);
  select * into v_try from daily_tries where id = p_try for update;
  if not found or v_try.player_id <> v_uid then
    raise exception 'unknown try';
  end if;
  if v_try.submitted_at is not null then
    raise exception 'try already sent';
  end if;
  if v_try.day < spikey_today() - 2 then
    raise exception 'try too old';
  end if;
  select * into v_row from daily_runs where day = v_try.day;
  if p_seed is distinct from v_row.seed or coalesce(p_season, -1) <> v_row.season then
    raise exception 'not that day''s map';
  end if;
  if p_loadout is not null and jsonb_typeof(p_loadout) = 'object'
     and length(p_loadout::text) <= 1024 then
    v_loadout := p_loadout;
  end if;
  if jsonb_typeof(v_taps) <> 'array' or jsonb_array_length(v_taps) > 20000 then
    raise exception 'invalid taps';
  end if;
  insert into runs (
    player_id, score, day, played_at, gameplay_version, seed, taps, loadout,
    season, coins, end_tick, revives, board
  )
  values (
    v_uid, p_score, v_try.day, now(), p_gameplay_version, v_row.seed, v_taps, v_loadout,
    v_row.season,
    case when p_coins between 0 and 100000 then p_coins end,
    case when p_end_tick between 0 and 10000000 then p_end_tick end,
    '[]'::jsonb, 'daily_run'
  )
  returning id into v_run;
  update daily_tries set submitted_at = now(), run_id = v_run where id = v_try.id;
end
$$;

-- The boards: 'daily' (Today: best endless run per player today), 'all_time'
-- (best endless run ever) and 'daily_run' (best try per player on today's
-- map). As 20261110095000_board_plates.sql, with Daily Run runs kept off the
-- first two. On 'daily_run' only the caller's own row carries its run: the
-- others are locked until the day is over ("locked": true).
create or replace function public.get_board(p_board text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_today date := spikey_today();
  v_run_board text := case when p_board = 'daily_run' then 'daily_run' else 'endless' end;
  v_result jsonb;
begin
  if p_board not in ('daily', 'all_time', 'daily_run') then
    raise exception 'unknown board %', p_board;
  end if;
  with best as (
    select distinct on (r.player_id) r.player_id, r.score, r.id as run_id,
           r.status = 'ok' as verified,
           jsonb_array_length(r.revives) > 0 as revived,
           coalesce(left(r.loadout->>'plate', 40), '') as plate
    from runs r
    where r.board = v_run_board
      and (p_board = 'all_time' or r.day = v_today)
      and (r.status = 'ok' or (r.status = 'pending' and r.player_id = auth.uid()))
    order by r.player_id, r.score desc, r.played_at asc
  ), ranked as (
    select b.player_id, b.score, b.run_id, b.verified, b.revived, b.plate, p.name, p.flyer,
           rank() over (order by b.score desc) as rank,
           p_board = 'daily_run' and b.player_id is distinct from auth.uid() as locked
    from best b
    join players p on p.id = b.player_id
  )
  select jsonb_build_object(
    'entries', coalesce((
      select jsonb_agg(jsonb_build_object(
        'rank', t.rank, 'name', t.name, 'flyer', t.flyer, 'score', t.score,
        'is_me', t.player_id = auth.uid(),
        'run', case when t.locked then null else t.run_id end,
        'locked', t.locked, 'verified', t.verified, 'revived', t.revived, 'plate', t.plate
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
      when p_board in ('daily', 'daily_run')
        then extract(epoch from spikey_next_midnight() - now())::integer
      else -1
    end
  ) into v_result;
  return v_result;
end
$$;

-- As before (20261110090000_revives.sql); a Daily Run run of a day not over
-- yet only plays for its own player.
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
    and (r.board <> 'daily_run' or r.day < spikey_today() or r.player_id = auth.uid())
$$;

-- As before (20261110100000_diamonds.sql), with the Daily Run prizes in the
-- list too; each prize says its board ('daily' or 'daily_run').
create or replace function public.get_wallet() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;
  perform spikey_settle_days();
  perform spikey_award_bonuses(v_uid);
  return jsonb_build_object(
    'diamonds', coalesce((select w.diamonds from wallets w where w.player_id = v_uid), 0),
    'bonuses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'kind', b.kind, 'ref', b.ref, 'diamonds', b.diamonds
      ) order by b.created_at, b.kind, b.ref)
      from bonus_prizes b
      where b.player_id = v_uid and b.claimed_at is null
    ), '[]'::jsonb),
    'prizes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'day', x.day, 'rank', x.rank, 'score', x.score, 'diamonds', x.diamonds,
        'board', x.board, 'number', x.number
      ) order by x.day, x.board)
      from (
        select p.day, p.rank, p.score, p.diamonds, 'daily' as board, null::integer as number
        from daily_prizes p
        where p.player_id = v_uid and p.claimed_at is null
        union all
        select p.day, p.rank, p.score, p.diamonds, 'daily_run', d.number
        from daily_run_prizes p
        left join daily_runs d on d.day = p.day
        where p.player_id = v_uid and p.claimed_at is null
      ) x
    ), '[]'::jsonb)
  );
end
$$;

-- As before (20261110100000_diamonds.sql), claiming the Daily Run prizes too.
create or replace function public.claim_prizes() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_prize record;
  v_claimed integer := 0;
  v_balance integer;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;
  perform spikey_settle_days();
  perform spikey_award_bonuses(v_uid);
  for v_prize in
    update daily_prizes
    set claimed_at = now()
    where player_id = v_uid and claimed_at is null
    returning day, diamonds
  loop
    v_balance := spikey_change_diamonds(
      v_uid, v_prize.diamonds, 'daily_prize', v_prize.day::text
    );
    v_claimed := v_claimed + v_prize.diamonds;
  end loop;
  for v_prize in
    update daily_run_prizes
    set claimed_at = now()
    where player_id = v_uid and claimed_at is null
    returning day, diamonds
  loop
    v_balance := spikey_change_diamonds(
      v_uid, v_prize.diamonds, 'daily_run_prize', v_prize.day::text
    );
    v_claimed := v_claimed + v_prize.diamonds;
  end loop;
  for v_prize in
    update bonus_prizes
    set claimed_at = now()
    where player_id = v_uid and claimed_at is null
    returning kind, ref, diamonds
  loop
    v_balance := spikey_change_diamonds(v_uid, v_prize.diamonds, v_prize.kind, v_prize.ref);
    v_claimed := v_claimed + v_prize.diamonds;
  end loop;
  if v_balance is null then
    v_balance := coalesce((select w.diamonds from wallets w where w.player_id = v_uid), 0);
  end if;
  return jsonb_build_object('diamonds', v_balance, 'claimed', v_claimed);
end
$$;

revoke all on function public.spikey_board_zone() from public, anon, authenticated;
revoke all on function public.spikey_daily_run_tries() from public, anon, authenticated;
revoke all on function public.spikey_daily_run_epoch() from public, anon, authenticated;
revoke all on function public.spikey_daily_run_prize(integer) from public, anon, authenticated;
revoke all on function public.spikey_season_of(date) from public, anon, authenticated;
revoke all on function public.spikey_daily_run_of(date) from public, anon, authenticated;
revoke all on function public.spikey_daily_run_places(date) from public, anon, authenticated;
revoke all on function public.spikey_settle_daily_runs() from public, anon, authenticated;
revoke all on function public.spikey_settle_days() from public, anon, authenticated;
revoke all on function public.spikey_day_places(date) from public, anon, authenticated;
revoke all on function public.get_daily_run() from public, anon;
revoke all on function public.start_daily_try(text, text) from public, anon;
revoke all on function public.submit_daily_run(
  uuid, text, text, integer, integer, bigint, jsonb, jsonb, integer, integer, integer
) from public, anon;
revoke all on function public.submit_run(
  text, text, integer, integer, bigint, jsonb, timestamptz, jsonb, integer, integer, integer, jsonb
) from public, anon;
revoke all on function public.get_board(text) from public, anon;
revoke all on function public.get_run(bigint) from public, anon;
revoke all on function public.get_wallet() from public, anon;
revoke all on function public.claim_prizes() from public, anon;
grant execute on function public.get_daily_run() to authenticated;
grant execute on function public.start_daily_try(text, text) to authenticated;
grant execute on function public.submit_daily_run(
  uuid, text, text, integer, integer, bigint, jsonb, jsonb, integer, integer, integer
) to authenticated;
grant execute on function public.submit_run(
  text, text, integer, integer, bigint, jsonb, timestamptz, jsonb, integer, integer, integer, jsonb
) to authenticated;
grant execute on function public.get_board(text) to authenticated;
grant execute on function public.get_run(bigint) to authenticated;
grant execute on function public.get_wallet() to authenticated;
grant execute on function public.claim_prizes() to authenticated;
