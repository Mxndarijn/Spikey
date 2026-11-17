-- The wins boards (docs/DUEL_MODE.md, section 5): who wins the most Battles
-- (and Duels, later). Each ended battle leaves one match_results row; whether
-- it counts is decided when it ends and stored with a reason, so the rules can
-- be tuned and the boards worked out again without losing a match.
--
-- What counts: a battle played out, or resigned from round 3 on. Never: a
-- battle closed with no result, resigned before round 3, played against a bot,
-- lost with runs averaging under 5 points (tanking), lost by an account under
-- 3 days old or with fewer than 20 checked runs (alt accounts). A friend
-- (invite) match counts at most 1 win per opponent a week and 3 all time;
-- random matches count in full. Draws count as played.

create table if not exists public.match_results (
  battle bigint primary key references public.battles (id) on delete cascade,
  mode text not null default 'battle' check (mode in ('battle', 'duel')),
  winner uuid references public.players (id) on delete cascade,
  loser uuid references public.players (id) on delete cascade,
  player_a uuid not null references public.players (id) on delete cascade,
  player_b uuid references public.players (id) on delete cascade,
  draw boolean not null default false,
  random boolean not null,
  ended_by text not null,
  counted boolean not null,
  reason text not null default '',
  finished_at timestamptz not null default now(),
  week date not null
);
create index if not exists match_results_week on public.match_results (mode, week) where counted;
create index if not exists match_results_a on public.match_results (player_a, finished_at);
create index if not exists match_results_b on public.match_results (player_b, finished_at);
alter table public.match_results enable row level security;

create or replace function public.spikey_wins_rules() returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'min_rounds_for_resign', 2, 'min_avg_score', 5, 'min_account_days', 3,
    'min_checked_runs', 20, 'friend_wins_per_week', 1, 'friend_wins_all_time', 3,
    'rate_min_all', 10, 'rate_min_week', 3
  )
$$;

-- The Monday a moment falls in, on the boards' clock (Amsterdam).
create or replace function public.spikey_week_of(p_at timestamptz) returns date
language sql stable as $$
  select date_trunc('week', p_at at time zone spikey_board_zone())::date
$$;

-- Whether an ended battle counts on the wins boards, and why not.
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

-- Replaces the hook in 0110_battles.sql: an ended battle leaves its result.
create or replace function public.spikey_battle_ended(p_battle bigint) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_b battles;
  v_c record;
begin
  select * into v_b from battles where id = p_battle;
  if v_b.player_b is null then
    return;
  end if;
  select * into v_c from spikey_match_counts(p_battle);
  insert into match_results (
    battle, winner, loser, player_a, player_b, draw, random, ended_by, counted, reason,
    finished_at, week
  )
  values (
    p_battle, v_b.winner,
    case when v_b.winner is null then null
         when v_b.winner = v_b.player_a then v_b.player_b else v_b.player_a end,
    v_b.player_a, v_b.player_b,
    v_b.winner is null and v_b.status = 'finished', v_b.random, coalesce(v_b.ended_by, 'played'),
    v_c.counted, v_c.reason, coalesce(v_b.finished_at, now()), spikey_week_of(coalesce(v_b.finished_at, now()))
  )
  on conflict (battle) do nothing;
end
$$;

-- One player's counted matches of a mode (and period): wins, losses, draws.
create or replace function public.spikey_wins_of(p_mode text, p_week date)
returns table (player_id uuid, wins integer, losses integer, draws integer, played integer, last_win timestamptz)
language sql stable as $$
  select p.player_id,
    count(*) filter (where p.player_id = m.winner)::integer,
    count(*) filter (where p.player_id = m.loser)::integer,
    count(*) filter (where m.draw)::integer,
    count(*)::integer,
    max(m.finished_at) filter (where p.player_id = m.winner)
  from match_results m
  cross join lateral (values (m.player_a), (m.player_b)) as p(player_id)
  where m.mode = p_mode and m.counted and (p_week is null or m.week = p_week)
  group by p.player_id
$$;

-- The wins board: 'week' (this week, Monday to Sunday on the boards' clock) or
-- 'all'. Ranked by counted wins; ties: higher win rate, then who got there
-- first. The win rate shows from 10 counted matches (this week: 3).
create or replace function public.get_wins_board(p_mode text, p_period text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_week date := case when p_period = 'week' then spikey_week_of(now()) end;
  v_min integer;
  v_result jsonb;
begin
  if p_mode not in ('battle', 'duel') or p_period not in ('week', 'all') then
    raise exception 'unknown wins board';
  end if;
  v_min := (spikey_wins_rules() ->> case when p_period = 'week' then 'rate_min_week' else 'rate_min_all' end)::integer;
  with w as (
    select x.*, x.wins::numeric / greatest(x.played, 1) as rate
    from spikey_wins_of(p_mode, v_week) x
    where x.wins > 0 or x.player_id = auth.uid()
  ), ranked as (
    select w.*, p.name, p.flyer,
      rank() over (order by w.wins desc, w.rate desc) as rank,
      row_number() over (order by w.wins desc, w.rate desc, w.last_win asc nulls last, p.name) as n
    from w join players p on p.id = w.player_id
    where w.wins > 0
  )
  select jsonb_build_object(
    'entries', coalesce((
      select jsonb_agg(jsonb_build_object(
        'rank', t.rank, 'name', t.name, 'flyer', t.flyer, 'wins', t.wins, 'losses', t.losses,
        'draws', t.draws, 'played', t.played,
        'rate', case when t.played >= v_min then round(t.rate * 100)::integer end,
        'is_me', t.player_id = auth.uid(), 'who', left(md5(t.player_id::text), 12)
      ) order by t.n)
      from (select * from ranked order by n limit 100) t
    ), '[]'::jsonb),
    'me', (
      select jsonb_build_object(
        'rank', (select r.rank from ranked r where r.player_id = auth.uid()),
        'wins', w.wins, 'losses', w.losses, 'draws', w.draws, 'played', w.played,
        'rate', case when w.played >= v_min then round(w.rate * 100)::integer end
      )
      from w where w.player_id = auth.uid()
    ),
    'players', (select count(*) from ranked),
    'resets_in_s', case when p_period = 'week'
      then extract(epoch from ((v_week + 7)::timestamp at time zone spikey_board_zone()) - now())::integer
      else -1 end,
    'rate_min', v_min
  ) into v_result;
  return v_result;
end
$$;

-- One player's record on a wins board (a tap on a row; `who` from the board):
-- counted wins, losses, draws, win rate, best streak of counted wins, and the
-- last 5 matches with how each ended.
create or replace function public.get_match_record(p_mode text, p_period text, p_who text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_week date := case when p_period = 'week' then spikey_week_of(now()) end;
  v_player uuid;
  v_row record;
  v_streak integer;
begin
  if p_mode not in ('battle', 'duel') or p_period not in ('week', 'all') then
    raise exception 'unknown wins board';
  end if;
  select p.id into v_player from players p where left(md5(p.id::text), 12) = p_who;
  if v_player is null then
    raise exception 'unknown player';
  end if;
  select * into v_row from spikey_wins_of(p_mode, v_week) x where x.player_id = v_player;
  select coalesce(max(len), 0)::integer into v_streak from (
    select count(*) as len from (
      select m.winner = v_player as won,
        row_number() over (order by m.finished_at)
          - row_number() over (partition by m.winner = v_player order by m.finished_at) as grp
      from match_results m
      where m.mode = p_mode and m.counted and (v_week is null or m.week = v_week)
        and v_player in (m.player_a, m.player_b)
    ) s
    where s.won
    group by s.grp
  ) g;
  return jsonb_build_object(
    'name', (select name from players where id = v_player),
    'flyer', (select flyer from players where id = v_player),
    'wins', coalesce(v_row.wins, 0), 'losses', coalesce(v_row.losses, 0),
    'draws', coalesce(v_row.draws, 0), 'played', coalesce(v_row.played, 0),
    'rate', case when coalesce(v_row.played, 0) >= (spikey_wins_rules() ->> case when p_period = 'week'
              then 'rate_min_week' else 'rate_min_all' end)::integer
            then round(v_row.wins * 100.0 / v_row.played)::integer end,
    'best_streak', v_streak,
    'last', coalesce((
      select jsonb_agg(x.j order by x.at desc) from (
        select m.finished_at as at, jsonb_build_object(
          'opponent', o.name, 'bot', o.bot,
          'result', case when m.draw then 'draw' when m.winner = v_player then 'won' else 'lost' end,
          'score', case when b.player_a = v_player then b.wins_a || '-' || b.wins_b
                        else b.wins_b || '-' || b.wins_a end,
          'how', case when m.ended_by = 'resigned' then 'resigned'
                      when m.random then 'random' else 'friend' end,
          'counted', m.counted
        ) as j
        from match_results m
        join battles b on b.id = m.battle
        left join players o on o.id = case when m.player_a = v_player then m.player_b else m.player_a end
        where m.mode = p_mode and v_player in (m.player_a, m.player_b)
          and (m.counted or v_player = auth.uid())
        order by m.finished_at desc
        limit 5
      ) x
    ), '[]'::jsonb)
  );
end
$$;

revoke all on function public.spikey_wins_rules() from public, anon;
revoke all on function public.spikey_week_of(timestamptz) from public, anon;
revoke all on function public.spikey_match_counts(bigint) from public, anon, authenticated;
revoke all on function public.spikey_battle_ended(bigint) from public, anon, authenticated;
revoke all on function public.spikey_wins_of(text, date) from public, anon, authenticated;
revoke all on function public.get_wins_board(text, text) from public, anon;
revoke all on function public.get_match_record(text, text, text) from public, anon;
grant execute on function public.get_wins_board(text, text) to authenticated;
grant execute on function public.get_match_record(text, text, text) to authenticated;
