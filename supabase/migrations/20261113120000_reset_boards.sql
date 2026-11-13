-- Version 23 starts the boards from zero (a development build: the old runs and
-- their replays are not kept). Every run is deleted, so the Daily and All-time
-- boards read as empty. Nothing else is lost:
--
--   kept as is   players, wallets, diamond_ledger, daily_prizes (paid and
--                unclaimed), bonus_prizes, settled_days, profiles, purchases.
--   paid first   finished days not settled yet are settled with the old runs
--                (spikey_settle_days) and every player's earned milestones and
--                streak diamonds are written (spikey_award_bonuses), so a prize
--                earned before the reset can still be claimed after it.
--   carried      what other rules read from old runs moves to two small tables:
--                  run_carry     per player: best checked score and the coins
--                                of runs that weren't rejected (gold ceiling).
--                  played_days   per player: days with a checked run (streaks).
--                spikey_gold_ceiling, spikey_award_bonuses and get_earn_status
--                read them next to the runs, so gold_excess, streaks and the
--                Earn screen's best go on as before the reset.
--   cleared      spot_state (remembered places on today's board, for push
--                alerts); alerts still queued become 'quiet' (never sent: the
--                places they speak of are gone).
--
-- Old app versions: runs sent after the reset are stored and checked as
-- always. The checker (server/run_checker.gd on main) marks a run of an older
-- gameplay version 'outdated', and the boards never show those. So once main
-- has GAMEPLAY_VERSION 23, runs from v22 apps never reach the new boards. This
-- file doesn't depend on that number: it works the same before or after the bump.
--
-- The reset itself is a function (spikey_reset_boards) so the database tests can
-- run it; only the database owner can call it. It runs once, at the bottom.

create table if not exists public.run_carry (
  player_id uuid primary key references public.players (id) on delete cascade,
  best integer not null default 0,
  coins bigint not null default 0
);

create table if not exists public.played_days (
  player_id uuid not null references public.players (id) on delete cascade,
  day date not null,
  primary key (player_id, day)
);

-- No policies: the game can't read or write these tables directly.
alter table public.run_carry enable row level security;
alter table public.played_days enable row level security;

-- The most gold a player could have: as before (20261110160000_paid_items.sql),
-- plus the coins of runs deleted by a reset.
create or replace function public.spikey_gold_ceiling(p_player uuid) returns bigint
language sql stable security definer set search_path = public as $$
  select
    coalesce((
      select sum(coalesce(coins, 0)) from runs
      where player_id = p_player and status <> 'rejected'
    ), 0)
    + coalesce((select c.coins from run_carry c where c.player_id = p_player), 0)
    + coalesce((
      select sum(-amount) * 100 from diamond_ledger
      where player_id = p_player and reason = 'convert' and amount < 0
    ), 0)
$$;

-- As before (20261110100000_diamonds.sql), with the best score and the days of
-- runs deleted by a reset counted too.
create or replace function public.spikey_award_bonuses(p_player uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_best integer;
begin
  select max(b.score) into v_best
  from (
    select r.score from runs r where r.player_id = p_player and r.status = 'ok'
    union all
    select c.best from run_carry c where c.player_id = p_player and c.best > 0
  ) b;
  if v_best is null then
    return;
  end if;
  insert into bonus_prizes (player_id, kind, ref, diamonds)
  select p_player, 'milestone', m.score::text, m.diamonds
  from (values (25, 1), (50, 1), (75, 2), (100, 3)) as m(score, diamonds)
  where v_best >= m.score
  on conflict (player_id, kind, ref) do nothing;
  -- The player's latest unbroken row of days with a checked run: one prize
  -- for its 7th day, one for its 14th, and so on.
  with days as (
    select r.day
    from runs r
    where r.player_id = p_player and r.status = 'ok' and r.day > spikey_today() - 400
    union
    select d.day
    from played_days d
    where d.player_id = p_player and d.day > spikey_today() - 400
  ), grouped as (
    select d.day, d.day - (row_number() over (order by d.day))::integer as grp
    from days d
  ), latest as (
    select min(g.day) as first_day, count(*)::integer as len
    from grouped g
    group by g.grp
    order by max(g.day) desc
    limit 1
  )
  insert into bonus_prizes (player_id, kind, ref, diamonds)
  select p_player, 'streak', (l.first_day + 7 * k - 1)::text, 1
  from latest l, generate_series(1, l.len / 7) as k
  on conflict (player_id, kind, ref) do nothing;
end
$$;

-- As before (20261111100000_earn_status.sql), with the best score and the days
-- of runs deleted by a reset counted too.
create or replace function public.get_earn_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_today date := spikey_today();
  v_first date;
  v_last date;
  v_len integer := 0;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;
  perform spikey_settle_days();
  perform spikey_award_bonuses(v_uid);
  -- The latest unbroken row of days, the same way spikey_award_bonuses finds it.
  with days as (
    select r.day
    from runs r
    where r.player_id = v_uid and r.status = 'ok' and r.day > v_today - 400
    union
    select d.day
    from played_days d
    where d.player_id = v_uid and d.day > v_today - 400
  ), grouped as (
    select d.day, d.day - (row_number() over (order by d.day))::integer as grp
    from days d
  )
  select min(g.day), max(g.day), count(*)::integer into v_first, v_last, v_len
  from grouped g
  group by g.grp
  order by max(g.day) desc
  limit 1;
  if v_last is null or v_last < v_today - 1 then
    v_len := 0;
  end if;
  return jsonb_build_object(
    'best', greatest(
      coalesce((
        select max(r.score) from runs r where r.player_id = v_uid and r.status = 'ok'
      ), 0),
      coalesce((select c.best from run_carry c where c.player_id = v_uid), 0)
    ),
    'milestones', coalesce((
      select jsonb_agg(b.ref::integer order by b.ref::integer)
      from bonus_prizes b
      where b.player_id = v_uid and b.kind = 'milestone'
    ), '[]'::jsonb),
    'streak', coalesce(v_len, 0),
    'played_today', coalesce(v_last = v_today, false),
    'streak_won', case when coalesce(v_len, 0) = 0 then 0 else (
      select count(*)::integer from bonus_prizes b
      where b.player_id = v_uid and b.kind = 'streak' and b.ref::date >= v_first
    ) end
  );
end
$$;

-- Empties the boards: pays what was earned, carries what other rules need,
-- then deletes every run. Returns how many runs it deleted.
create or replace function public.spikey_reset_boards() returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_player uuid;
  v_count integer;
begin
  perform spikey_settle_days();
  for v_player in select distinct r.player_id from runs r where r.status = 'ok' loop
    perform spikey_award_bonuses(v_player);
  end loop;
  insert into run_carry (player_id, best, coins)
  select r.player_id,
         coalesce(max(r.score) filter (where r.status = 'ok'), 0),
         coalesce(sum(coalesce(r.coins, 0)) filter (where r.status <> 'rejected'), 0)
  from runs r
  group by r.player_id
  on conflict (player_id) do update
    set best = greatest(run_carry.best, excluded.best),
        coins = run_carry.coins + excluded.coins;
  insert into played_days (player_id, day)
  select distinct r.player_id, r.day from runs r where r.status = 'ok'
  on conflict do nothing;
  delete from spot_state;
  update spot_alerts set status = 'quiet' where status = 'queued';
  delete from runs;
  get diagnostics v_count = row_count;
  return v_count;
end
$$;

revoke all on function public.spikey_gold_ceiling(uuid) from public, anon, authenticated;
revoke all on function public.spikey_award_bonuses(uuid) from public, anon, authenticated;
revoke all on function public.spikey_reset_boards() from public, anon, authenticated;
revoke all on function public.get_earn_status() from public, anon;
grant execute on function public.get_earn_status() to authenticated;

select public.spikey_reset_boards();
