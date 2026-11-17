-- The shared-IP rule for the wins boards (docs/DUEL_MODE.md, section 5): a
-- match never counts when both players used the same internet address while
-- it ran (two accounts on one phone or one home farming wins). The server
-- notes a salted hash of the address of every Battle operation and every Duel
-- sign-in (backend.note_ip, from app.rs and duel_ws.rs), one row per player,
-- address and day, kept 7 days. The address itself is never stored.

create table if not exists backend.player_ips (
  player_id uuid not null,
  ip_hash text not null,
  day date not null default current_date,
  primary key (player_id, ip_hash, day)
);
create index if not exists player_ips_hash on backend.player_ips (ip_hash, day);

insert into public.worker_settings (key, value)
values ('ip_salt', md5(gen_random_uuid()::text || gen_random_uuid()::text))
on conflict (key) do nothing;

create or replace function backend.note_ip(p_player uuid, p_ip text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_player is null or coalesce(p_ip, '') in ('', 'unknown') then
    return;
  end if;
  insert into backend.player_ips (player_id, ip_hash)
  values (
    p_player,
    encode(sha256(convert_to(
      coalesce((select value from worker_settings where key = 'ip_salt'), '') || '|' || p_ip, 'UTF8'
    )), 'hex')
  )
  on conflict do nothing;
  delete from backend.player_ips where day < current_date - 7;
end
$$;

-- Both players used one address on a day from `p_from` to `p_to`.
create or replace function public.spikey_shared_ip(
  p_a uuid, p_b uuid, p_from timestamptz, p_to timestamptz
) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from backend.player_ips x
    join backend.player_ips y on y.ip_hash = x.ip_hash and y.day = x.day
    where x.player_id = p_a and y.player_id = p_b
      and x.day between (p_from - interval '1 day')::date and p_to::date
  )
$$;

-- As in 0111_wins_boards.sql, with the shared-IP rule.
create or replace function public.spikey_match_counts(p_battle bigint)
returns table (counted boolean, reason text)
language plpgsql stable security definer set search_path = public as $$
declare
  v_b battles;
  v_rules jsonb := spikey_wins_rules();
  v_loser uuid;
  v_rounds integer;
  v_avg numeric;
  v_loser_a boolean;
begin
  select * into v_b from battles where id = p_battle;
  if v_b.status = 'closed' or v_b.ended_by = 'closed' then
    return query select false, 'closed'::text;
    return;
  end if;
  if exists (select 1 from players where id in (v_b.player_a, v_b.player_b) and bot) then
    return query select false, 'bot'::text;
    return;
  end if;
  select count(*)::integer into v_rounds from battle_rounds where battle = p_battle and settled;
  if v_b.ended_by = 'resigned' and v_rounds < (v_rules ->> 'min_rounds_for_resign')::integer then
    return query select false, 'resigned early'::text;
    return;
  end if;
  if v_b.player_b is not null and spikey_shared_ip(
       v_b.player_a, v_b.player_b, v_b.created_at, coalesce(v_b.finished_at, now())) then
    return query select false, 'shared ip'::text;
    return;
  end if;
  if v_b.winner is null then
    return query select true, 'draw'::text;
    return;
  end if;
  v_loser := case when v_b.winner = v_b.player_a then v_b.player_b else v_b.player_a end;
  v_loser_a := v_loser = v_b.player_a;
  if v_b.ended_by = 'played' then
    select avg(coalesce(case when v_loser_a then sa.score else sb.score end, 0)) into v_avg
    from battle_rounds r,
      lateral spikey_battle_side(r.run_a, r.lost_a) sa,
      lateral spikey_battle_side(r.run_b, r.lost_b) sb
    where r.battle = p_battle and r.settled;
    if coalesce(v_avg, 0) < (v_rules ->> 'min_avg_score')::numeric then
      return query select false, 'loser under 5 points'::text;
      return;
    end if;
  end if;
  if coalesce((select created_at from auth.users where id = v_loser), now())
       > now() - make_interval(days => (v_rules ->> 'min_account_days')::integer)
     or (select count(*) from runs where player_id = v_loser and status = 'ok')
       < (v_rules ->> 'min_checked_runs')::integer then
    return query select false, 'new account'::text;
    return;
  end if;
  if not v_b.random then
    if (select count(*) from match_results m
        where m.counted and m.winner = v_b.winner and m.loser = v_loser and not m.random
          and m.week = spikey_week_of(now()))
         >= (v_rules ->> 'friend_wins_per_week')::integer
       or (select count(*) from match_results m
        where m.counted and m.winner = v_b.winner and m.loser = v_loser and not m.random)
         >= (v_rules ->> 'friend_wins_all_time')::integer then
      return query select false, 'friend cap'::text;
      return;
    end if;
  end if;
  return query select true, ''::text;
end
$$;

-- As in 0113_duel.sql, with the shared-IP rule.
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
  elsif spikey_shared_ip(p_a, p_b, now() - interval '1 hour', now()) then
    v_counted := false;
    v_reason := 'shared ip';
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

revoke all on function backend.note_ip(uuid, text) from public, anon, authenticated;
revoke all on function public.spikey_shared_ip(uuid, uuid, timestamptz, timestamptz)
  from public, anon, authenticated;
