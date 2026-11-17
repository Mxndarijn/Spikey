-- Battle and Duel run only on the newest gameplay version (the user's rule).
-- The server checks every run with one sim, its own, so it never needs an old
-- one: a phone on an older version is told update_required (the server checks
-- the X-Flapjaw-Gameplay header of every battle operation and the Duel hello,
-- backend/src/app.rs and duel_ws.rs), and when the server starts on a newer
-- version, every round not decided yet that was dealt on an older one is
-- played again: the same round number, a new seed on the new version, its old
-- runs dropped (also when only one player had played it), from its opener.
-- Decided rounds and the battle's score stay. Both players hear
-- "New game version: round N starts over".

-- One round dealt again on `p_version`.
create or replace function public.spikey_battle_redeal_round(
  p_battle bigint, p_number integer, p_version integer
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_b battles;
begin
  update battle_rounds
  set seed = spikey_battle_seed(), season = spikey_season_of(spikey_today()),
      gameplay_version = p_version,
      run_a = null, run_b = null, started_a = null, started_b = null,
      lost_a = false, lost_b = false
  where battle = p_battle and number = p_number and not settled;
  update battles set gameplay_version = greatest(gameplay_version, p_version), reminded = 0
  where id = p_battle
  returning * into v_b;
  perform spikey_battle_refresh(p_battle);
  perform spikey_battle_alert(v_b.player_a, 'redeal:' || p_battle || ':' || p_number || ':' || p_version,
    'New game version', 'Round ' || p_number || ' starts over');
  perform spikey_battle_alert(v_b.player_b, 'redeal:' || p_battle || ':' || p_number || ':' || p_version,
    'New game version', 'Round ' || p_number || ' starts over');
end
$$;

-- At the server's start (backend/src/main.rs): every round not decided yet on
-- a version older than the server's is dealt again. Returns how many.
create or replace function public.spikey_battle_redeal_old(p_version integer) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v record;
  v_n integer := 0;
begin
  for v in
    select r.battle, r.number
    from battle_rounds r
    join battles b on b.id = r.battle
    where b.status in ('waiting', 'open') and not r.settled and r.gameplay_version < p_version
    order by r.battle, r.number
  loop
    perform spikey_battle_redeal_round(v.battle, v.number, p_version);
    v_n := v_n + 1;
  end loop;
  update battles set gameplay_version = p_version
  where status in ('waiting', 'open') and gameplay_version < p_version;
  return v_n;
end
$$;

-- As in 0110_battles.sql, with the version rules above: a phone older than
-- the round is told update_required; a round older than the phone is dealt
-- again for both.
create or replace function public.battle_start_run(
  p_battle bigint, p_round integer, p_gameplay_version integer
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_b battles := spikey_battle_mine(p_battle);
  v_mine_a boolean := v_b.player_a = auth.uid();
  v_next record;
  v_r battle_rounds;
  v_started timestamptz;
  v_run bigint;
  v_lost boolean := false;
begin
  select * into v_next from spikey_battle_next(p_battle, v_uid) limit 1;
  if v_next.number is null or v_next.number <> p_round then
    raise exception 'not your turn';
  end if;
  if v_next.role = 'open' and not exists (
    select 1 from battle_rounds where battle = p_battle and number = p_round
  ) then
    insert into battle_rounds (battle, number, seed, season, gameplay_version, first_player, blind)
    values (
      p_battle, p_round, spikey_battle_seed(), spikey_season_of(spikey_today()),
      p_gameplay_version, v_uid,
      v_b.wins_a = v_b.first_to - 1 and v_b.wins_b = v_b.first_to - 1
    );
  end if;
  select * into v_r from battle_rounds where battle = p_battle and number = p_round for update;
  if v_r.gameplay_version > p_gameplay_version then
    raise exception 'update_required';
  end if;
  if v_r.gameplay_version < p_gameplay_version then
    -- Dealt on an older version (the server's start redeals these first): the
    -- same round again on this one, from its opener.
    perform spikey_battle_redeal_round(p_battle, p_round, p_gameplay_version);
    select * into v_r from battle_rounds where battle = p_battle and number = p_round for update;
    if v_r.first_player <> v_uid then
      return spikey_battle_view(p_battle, v_uid) || jsonb_build_object('redealt', true);
    end if;
  end if;
  v_started := case when v_mine_a then v_r.started_a else v_r.started_b end;
  v_run := case when v_mine_a then v_r.run_a else v_r.run_b end;
  if v_started is not null and v_run is null then
    v_lost := true;
    if v_mine_a then
      update battle_rounds set lost_a = true where battle = p_battle and number = p_round;
    else
      update battle_rounds set lost_b = true where battle = p_battle and number = p_round;
    end if;
    update battles set last_move_at = now(), reminded = 0 where id = p_battle;
    perform spikey_battle_settle(p_battle, p_round);
    perform spikey_battle_refresh(p_battle);
    return spikey_battle_view(p_battle, v_uid) || jsonb_build_object('lost', true);
  end if;
  if v_mine_a then
    update battle_rounds set started_a = now() where battle = p_battle and number = p_round;
  else
    update battle_rounds set started_b = now() where battle = p_battle and number = p_round;
  end if;
  return jsonb_build_object(
    'battle', p_battle, 'round', p_round, 'seed', v_r.seed, 'season', v_r.season,
    'blind', v_r.blind, 'lost', v_lost
  );
end
$$;


revoke all on function public.spikey_battle_redeal_round(bigint, integer, integer) from public, anon, authenticated;
revoke all on function public.spikey_battle_redeal_old(integer) from public, anon, authenticated;
