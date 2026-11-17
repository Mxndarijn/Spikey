-- Duel (docs/DUEL_MODE.md, section 3): a live best of three. The match itself
-- lives in the server's memory (backend/src/duel.rs, duel_ws.rs) and only its
-- result is stored: one battles row (mode 'duel') and its match_results row for
-- the wins boards. The rounds' runs are not stored: the server stepped both
-- sims itself while they flew.
--
-- What counts on the Duel board: a match played out, or one the loser left
-- after the first round. Never: one left before a round was decided, or lost
-- by an account under 3 days old or with fewer than 20 checked runs. A friend
-- (invite) match counts at most 1 win per opponent a week and 3 all time.

alter table public.battles add column if not exists mode text not null default 'battle'
  check (mode in ('battle', 'duel'));
alter table public.battles drop constraint if exists battles_ended_by_check;
alter table public.battles add constraint battles_ended_by_check
  check (ended_by in ('played', 'resigned', 'closed', 'left'));

-- As in 0110_battles.sql, Battle's list leaves Duel matches out.
create or replace function public.battle_list() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;
  return jsonb_build_object('battles', coalesce((
    select jsonb_agg(spikey_battle_view(b.id, v_uid) - 'rounds' order by
      (b.turn_player = v_uid) desc nulls last, b.status in ('finished', 'closed'),
      b.last_move_at desc)
    from battles b
    where (b.player_a = v_uid or b.player_b = v_uid) and b.mode = 'battle'
      and (b.status in ('waiting', 'open') or b.finished_at > now() - interval '30 days')
  ), '[]'::jsonb), 'limits', spikey_battle_limits());
end
$$;

-- A Duel match that ended (the server, never a phone). Returns the result row's
-- id (the battle). p_winner null: a draw (or nobody, when left before a round).
create or replace function public.duel_record(
  p_a uuid, p_b uuid, p_winner uuid, p_ended_by text, p_rounds integer,
  p_random boolean, p_wins_a integer, p_wins_b integer, p_gameplay_version integer
) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_rules jsonb := spikey_wins_rules();
  v_id bigint;
  v_loser uuid;
  v_counted boolean := true;
  v_reason text := '';
begin
  insert into battles (
    player_a, player_b, random, first_to, status, gameplay_version, wins_a, wins_b,
    finished_at, ended_by, winner, mode, last_move_at
  )
  values (
    p_a, p_b, coalesce(p_random, false), 2, 'finished',
    coalesce(p_gameplay_version, 0), coalesce(p_wins_a, 0), coalesce(p_wins_b, 0),
    now(), p_ended_by, p_winner, 'duel', now()
  )
  returning id into v_id;
  v_loser := case when p_winner is null then null when p_winner = p_a then p_b else p_a end;
  if p_ended_by = 'left' and coalesce(p_rounds, 0) < 1 then
    v_counted := false;
    v_reason := 'left early';
  elsif v_loser is not null and (
    coalesce((select created_at from auth.users where id = v_loser), now())
      > now() - make_interval(days => (v_rules ->> 'min_account_days')::integer)
    or (select count(*) from runs where player_id = v_loser and status = 'ok')
      < (v_rules ->> 'min_checked_runs')::integer) then
    v_counted := false;
    v_reason := 'new account';
  elsif v_loser is not null and not coalesce(p_random, false) and (
    (select count(*) from match_results m
     where m.mode = 'duel' and m.counted and m.winner = p_winner and m.loser = v_loser
       and not m.random and m.week = spikey_week_of(now()))
      >= (v_rules ->> 'friend_wins_per_week')::integer
    or (select count(*) from match_results m
     where m.mode = 'duel' and m.counted and m.winner = p_winner and m.loser = v_loser and not m.random)
      >= (v_rules ->> 'friend_wins_all_time')::integer) then
    v_counted := false;
    v_reason := 'friend cap';
  elsif p_winner is null then
    v_reason := 'draw';
  end if;
  insert into match_results (
    battle, mode, winner, loser, player_a, player_b, draw, random, ended_by, counted, reason,
    finished_at, week
  )
  values (
    v_id, 'duel', p_winner, v_loser, p_a, p_b, p_winner is null and p_ended_by = 'played',
    coalesce(p_random, false), p_ended_by, v_counted, v_reason, now(), spikey_week_of(now())
  );
  return v_id;
end
$$;

-- The name and flyer the Duel screens show for a player.
create or replace function public.duel_player(p_player uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('name', coalesce(name, 'Flyer'), 'flyer', coalesce(flyer, 'buzz'))
  from (select 1) one left join players p on p.id = p_player
$$;

revoke all on function public.duel_record(uuid, uuid, uuid, text, integer, boolean, integer, integer, integer)
  from public, anon, authenticated;
revoke all on function public.duel_player(uuid) from public, anon, authenticated;
