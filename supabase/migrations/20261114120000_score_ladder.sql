-- Score ladder: past the four best-score milestones (25, 50, 75, 100), every
-- 50 points up to 1000 (150, 200, ..., 1000: 18 steps) wins LADDER_PRIZE (3)
-- diamonds, once per player, when their best checked score first reaches the
-- step. A run that passes several steps pays each. Same table and kind as
-- the other milestones (bonus_prizes, kind 'milestone', ref "150"), so
-- get_wallet, claim_prizes and the prize popup need no change.
--
--   ladder_marks   per player: their best checked score when this file was
--                  applied. Steps at or below it never pay (no back-pay for
--                  old bests); a player without a row starts at 0.
--
-- The phone keeps the same numbers in EarnRules (LADDER_*). To change the
-- steps, change spikey_award_bonuses below and EarnRules together.

create table if not exists public.ladder_marks (
  player_id uuid primary key references public.players (id) on delete cascade,
  best integer not null default 0
);

-- No policies: the game can't read or write this table directly.
alter table public.ladder_marks enable row level security;

-- Marks every player's best checked score (runs and what a reset carried) as
-- their ladder start. A player already marked keeps their mark. Runs once, at
-- the bottom; the database tests call it too.
create or replace function public.spikey_mark_ladder() returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_count integer;
begin
  insert into ladder_marks (player_id, best)
  select b.player_id, max(b.score)
  from (
    select r.player_id, r.score from runs r where r.status = 'ok'
    union all
    select c.player_id, c.best from run_carry c where c.best > 0
  ) b
  group by b.player_id
  on conflict (player_id) do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end
$$;

-- As before (20261113120000_reset_boards.sql), plus the ladder steps above the
-- player's mark.
create or replace function public.spikey_award_bonuses(p_player uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_best integer;
  v_mark integer;
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
  -- The ladder: 150 to 1000 in steps of 50, 3 diamonds each, above the mark.
  v_mark := coalesce((select l.best from ladder_marks l where l.player_id = p_player), 0);
  insert into bonus_prizes (player_id, kind, ref, diamonds)
  select p_player, 'milestone', s::text, 3
  from generate_series(150, least(v_best, 1000), 50) as s
  where s > v_mark
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

-- As before (20261113120000_reset_boards.sql), plus "ladder_mark": the best
-- at or below which ladder steps don't pay (0 for players who came later).
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
    'ladder_mark', coalesce((select l.best from ladder_marks l where l.player_id = v_uid), 0),
    'streak', coalesce(v_len, 0),
    'played_today', coalesce(v_last = v_today, false),
    'streak_won', case when coalesce(v_len, 0) = 0 then 0 else (
      select count(*)::integer from bonus_prizes b
      where b.player_id = v_uid and b.kind = 'streak' and b.ref::date >= v_first
    ) end
  );
end
$$;

revoke all on function public.spikey_mark_ladder() from public, anon, authenticated;
revoke all on function public.spikey_award_bonuses(uuid) from public, anon, authenticated;
revoke all on function public.get_earn_status() from public, anon;
grant execute on function public.get_earn_status() to authenticated;

select public.spikey_mark_ladder();
