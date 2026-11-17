-- Battle (docs/DUEL_MODE.md, section 2): two players take turns on the same
-- server seeds, first to 6 round wins. The player who starts a battle opens
-- round 1, then the opener alternates (odd rounds A, even rounds B); a round
-- played at 5-5 (first_to - 1 each) is blind: neither sees the other's run
-- before playing it. Each turn answers one round and opens the next.
--
-- No timers: a battle waits as long as it takes. Nudges after 1 and 3 days
-- (spikey_battle_reminders, called by the server every few minutes), Resign
-- any time, Close with no result after 7 days waiting on the other player.
--
-- Runs are ordinary runs (board 'battle'), checked by the server's replay
-- check like any other; a round is decided once both of its runs are checked
-- (a trigger on runs). A rejected run, or one that never arrived, counts as 0.

alter table public.runs drop constraint if exists runs_board_check;
alter table public.runs add constraint runs_board_check
  check (board in ('endless', 'daily_run', 'battle'));

-- Bots (docs/DUEL_MODE.md, section 6) are players too, marked here.
alter table public.players add column if not exists bot boolean not null default false;

create table if not exists public.battles (
  id bigint generated always as identity primary key,
  player_a uuid not null references public.players (id) on delete cascade,
  player_b uuid references public.players (id) on delete cascade,
  random boolean not null default false,
  invite_hash text unique,
  first_to integer not null default 6 check (first_to between 1 and 10),
  status text not null default 'waiting'
    check (status in ('waiting', 'open', 'finished', 'closed')),
  gameplay_version integer not null,
  turn_player uuid,
  wins_a integer not null default 0,
  wins_b integer not null default 0,
  created_at timestamptz not null default now(),
  last_move_at timestamptz not null default now(),
  finished_at timestamptz,
  ended_by text check (ended_by in ('played', 'resigned', 'closed')),
  winner uuid,
  nudged_at timestamptz,
  reminded integer not null default 0
);
create index if not exists battles_a on public.battles (player_a, status);
create index if not exists battles_b on public.battles (player_b, status);
create index if not exists battles_waiting on public.battles (gameplay_version, created_at)
  where status = 'waiting' and random;

create table if not exists public.battle_rounds (
  battle bigint not null references public.battles (id) on delete cascade,
  number integer not null check (number between 1 and 13),
  seed bigint not null check (seed between 0 and 4294967295),
  season integer not null,
  gameplay_version integer not null,
  first_player uuid not null,
  blind boolean not null default false,
  run_a bigint references public.runs (id) on delete set null,
  run_b bigint references public.runs (id) on delete set null,
  started_a timestamptz,
  started_b timestamptz,
  lost_a boolean not null default false,
  lost_b boolean not null default false,
  settled boolean not null default false,
  winner uuid,
  primary key (battle, number)
);
create index if not exists battle_rounds_run_a on public.battle_rounds (run_a);
create index if not exists battle_rounds_run_b on public.battle_rounds (run_b);

alter table public.battles enable row level security;
alter table public.battle_rounds enable row level security;

-- Battle alerts: an outbox beside the board alerts' (spot_alerts), sent by the
-- same sender. The sender sees them with negative ids and on their own
-- Android channel ("line": "battle").
create table if not exists public.battle_alerts (
  id bigint generated always as identity primary key,
  player_id uuid not null references public.players (id) on delete cascade,
  ref text not null,
  title text not null,
  body text not null,
  status text not null default 'queued'
    check (status in ('queued', 'sent', 'failed', 'no_device')),
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  unique (player_id, ref)
);
create index if not exists battle_alerts_queued on public.battle_alerts (id) where status = 'queued';
alter table public.battle_alerts enable row level security;

-- As before (20261110110000_push_alerts.sql), plus the battle alerts.
create or replace function public.worker_pending_alerts(p_limit integer default 100) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x.alert order by x.at), '[]'::jsonb)
  from (
    select a.created_at as at, jsonb_build_object(
      'id', a.id, 'token', d.token, 'platform', d.platform, 'title', a.title, 'body', a.body,
      'line', a.line
    ) as alert
    from (
      select * from spot_alerts
      where status = 'queued' and created_at > now() - interval '30 minutes'
      order by id
      limit greatest(1, least(coalesce(p_limit, 100), 500))
    ) a
    join push_devices d on d.player_id = a.player_id and d.enabled
    union all
    select a.created_at, jsonb_build_object(
      'id', -a.id, 'token', d.token, 'platform', d.platform, 'title', a.title, 'body', a.body,
      'line', 'battle'
    )
    from (
      select * from battle_alerts
      where status = 'queued' and created_at > now() - interval '30 minutes'
      order by id
      limit greatest(1, least(coalesce(p_limit, 100), 500))
    ) a
    join push_devices d on d.player_id = a.player_id and d.enabled
  ) x
$$;

-- As before, plus the battle alerts (negative ids).
create or replace function public.worker_mark_alerts(p_results jsonb) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_count integer;
  v_more integer;
begin
  delete from push_devices d
  using jsonb_to_recordset(p_results) as x(id bigint, status text, forget_token boolean),
        spot_alerts a
  where x.id > 0 and a.id = x.id and d.player_id = a.player_id and coalesce(x.forget_token, false);
  delete from push_devices d
  using jsonb_to_recordset(p_results) as x(id bigint, status text, forget_token boolean),
        battle_alerts a
  where x.id < 0 and a.id = -x.id and d.player_id = a.player_id and coalesce(x.forget_token, false);
  update spot_alerts a
  set status = x.status, sent_at = now()
  from jsonb_to_recordset(p_results) as x(id bigint, status text)
  where x.id > 0 and a.id = x.id and a.status = 'queued' and x.status in ('sent', 'failed');
  get diagnostics v_count = row_count;
  update battle_alerts a
  set status = x.status, sent_at = now()
  from jsonb_to_recordset(p_results) as x(id bigint, status text)
  where x.id < 0 and a.id = -x.id and a.status = 'queued' and x.status in ('sent', 'failed');
  get diagnostics v_more = row_count;
  return v_count + v_more;
end
$$;

-- The rules' numbers, in one place (meta/match_rules.gd holds the same).
create or replace function public.spikey_battle_limits() returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'first_to', 6, 'max_rounds', 13, 'open', 20, 'random_waiting', 5,
    'creates_per_day', 30, 'close_after_days', 7, 'copied_taps', 30
  )
$$;

-- A new seed: 32 random bits.
create or replace function public.spikey_battle_seed() returns bigint
language sql volatile as $$
  select ('x' || substr(md5(gen_random_uuid()::text), 1, 8))::bit(32)::bigint
$$;

-- An invite code: 6 characters with no look-alikes (no 0/O, 1/I/L).
create or replace function public.spikey_battle_code() returns text
language plpgsql volatile as $$
declare
  v_abc text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_raw bytea := uuid_send(gen_random_uuid());
  v_code text := '';
begin
  for i in 0..5 loop
    v_code := v_code || substr(v_abc, 1 + get_byte(v_raw, i) % length(v_abc), 1);
  end loop;
  return v_code;
end
$$;

create or replace function public.spikey_battle_code_hash(p_code text) returns text
language sql immutable as $$
  select md5('flapjaw-battle:' || upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g')))
$$;

-- True when `p_taps` follows `p_rival` within one tick for more than
-- `copied_taps` taps in a row: a modded app replaying the rival's run (honest
-- players never match frame-exact). Both are ascending tick lists.
create or replace function public.spikey_taps_copied(p_taps jsonb, p_rival jsonb) returns boolean
language plpgsql immutable as $$
declare
  v_a integer[];
  v_b integer[];
  v_j integer := 1;
  v_streak integer := 0;
  v_limit integer := (spikey_battle_limits() ->> 'copied_taps')::integer;
begin
  if p_taps is null or p_rival is null
     or jsonb_typeof(p_taps) <> 'array' or jsonb_typeof(p_rival) <> 'array' then
    return false;
  end if;
  select coalesce(array_agg(x::integer order by o), '{}') into v_a
  from jsonb_array_elements_text(p_taps) with ordinality as t(x, o);
  select coalesce(array_agg(x::integer order by o), '{}') into v_b
  from jsonb_array_elements_text(p_rival) with ordinality as t(x, o);
  if coalesce(array_length(v_a, 1), 0) <= v_limit or coalesce(array_length(v_b, 1), 0) <= v_limit then
    return false;
  end if;
  for i in 1..array_length(v_a, 1) loop
    while v_j <= array_length(v_b, 1) and v_b[v_j] < v_a[i] - 1 loop
      v_j := v_j + 1;
    end loop;
    if v_j <= array_length(v_b, 1) and abs(v_b[v_j] - v_a[i]) <= 1 then
      v_streak := v_streak + 1;
      if v_streak > v_limit then
        return true;
      end if;
    else
      v_streak := 0;
    end if;
  end loop;
  return false;
end
$$;

-- One side of a round: its score and coins once known; null while its run is
-- not played or not checked yet. A rejected or lost run is 0.
create or replace function public.spikey_battle_side(p_run bigint, p_lost boolean)
returns table (known boolean, score integer, coins integer)
language plpgsql stable as $$
declare
  v_run runs;
begin
  if p_lost then
    return query select true, 0, 0;
    return;
  end if;
  if p_run is null then
    return query select false, null::integer, null::integer;
    return;
  end if;
  select * into v_run from runs where id = p_run;
  if not found or v_run.status in ('rejected', 'outdated') then
    return query select true, 0, 0;
  elsif v_run.status = 'ok' then
    return query select true, v_run.score, coalesce(v_run.coins, 0);
  else
    return query select false, null::integer, null::integer;
  end if;
end
$$;

-- The round a player plays next and how: ('answer', n) when the other
-- opened round n, ('open', n) for a new round, or null when it's not their
-- turn (or the battle is over).
create or replace function public.spikey_battle_next(p_battle bigint, p_player uuid)
returns table (number integer, role text)
language plpgsql stable as $$
declare
  v_b battles;
  v_r battle_rounds;
  v_mine_a boolean;
  v_opener uuid;
begin
  select * into v_b from battles where id = p_battle;
  if not found or v_b.status not in ('waiting', 'open') then
    return;
  end if;
  v_mine_a := v_b.player_a = p_player;
  select * into v_r from battle_rounds r where r.battle = p_battle order by r.number desc limit 1;
  if not found then
    if v_mine_a then
      return query select 1, 'open'::text;
    end if;
    return;
  end if;
  -- The newest round: the opener plays first, then the other answers.
  if v_r.first_player = v_b.player_a then
    if v_r.run_a is null and not v_r.lost_a then
      if v_mine_a then return query select v_r.number, 'open'::text; end if;
      return;
    end if;
    if v_r.run_b is null and not v_r.lost_b then
      if not v_mine_a and v_b.player_b is not null then
        return query select v_r.number, 'answer'::text;
      end if;
      return;
    end if;
  else
    if v_r.run_b is null and not v_r.lost_b then
      if not v_mine_a then return query select v_r.number, 'open'::text; end if;
      return;
    end if;
    if v_r.run_a is null and not v_r.lost_a then
      if v_mine_a then return query select v_r.number, 'answer'::text; end if;
      return;
    end if;
  end if;
  -- Both played: the next round's opener is this round's answerer.
  if v_r.number >= (spikey_battle_limits() ->> 'max_rounds')::integer then
    return;
  end if;
  v_opener := case when (v_r.number + 1) % 2 = 1 then v_b.player_a else v_b.player_b end;
  if v_opener = p_player then
    return query select v_r.number + 1, 'open'::text;
  end if;
end
$$;

-- An alert in the battle outbox, once per ref (a nudge per day, a turn per
-- round); none for a bot.
create or replace function public.spikey_battle_alert(
  p_player uuid, p_ref text, p_title text, p_body text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_player is null or exists (select 1 from players where id = p_player and bot) then
    return;
  end if;
  insert into battle_alerts (player_id, ref, title, body, status)
  values (
    p_player, p_ref, p_title, p_body,
    case when exists (select 1 from push_devices d where d.player_id = p_player and d.enabled)
      then 'queued' else 'no_device' end
  )
  on conflict (player_id, ref) do nothing;
exception when others then
  null;
end
$$;

-- Whose turn it is now; stored, so lists and reminders are cheap.
create or replace function public.spikey_battle_refresh(p_battle bigint) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_b battles;
  v_turn uuid;
begin
  select * into v_b from battles where id = p_battle;
  if v_b.status not in ('waiting', 'open') then
    update battles set turn_player = null where id = p_battle;
    return null;
  end if;
  if exists (select 1 from spikey_battle_next(p_battle, v_b.player_a)) then
    v_turn := v_b.player_a;
  elsif v_b.player_b is not null and exists (select 1 from spikey_battle_next(p_battle, v_b.player_b)) then
    v_turn := v_b.player_b;
  end if;
  update battles set turn_player = v_turn where id = p_battle;
  return v_turn;
end
$$;

-- Hook for the wins boards (0111_wins_boards.sql): a battle just ended.
create or replace function public.spikey_battle_ended(p_battle bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  null;
end
$$;

-- Ends a battle: finished (someone won, or a draw after the last round),
-- resigned or closed. Tells both players.
create or replace function public.spikey_battle_end(
  p_battle bigint, p_status text, p_ended_by text, p_winner uuid
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_b battles;
  v_name_a text;
  v_name_b text;
  v_score text;
begin
  update battles
  set status = p_status, ended_by = p_ended_by, winner = p_winner,
      finished_at = now(), turn_player = null
  where id = p_battle
  returning * into v_b;
  select name into v_name_a from players where id = v_b.player_a;
  select name into v_name_b from players where id = v_b.player_b;
  v_score := v_b.wins_a || '-' || v_b.wins_b;
  if p_ended_by = 'played' then
    if p_winner = v_b.player_a then
      perform spikey_battle_alert(v_b.player_a, 'end:' || p_battle, 'You won the battle',
        'You beat ' || coalesce(v_name_b, 'your rival') || ' ' || v_score);
      perform spikey_battle_alert(v_b.player_b, 'end:' || p_battle, 'Battle over',
        coalesce(v_name_a, 'Your rival') || ' won ' || v_b.wins_a || '-' || v_b.wins_b || '. Rematch?');
    elsif p_winner = v_b.player_b then
      perform spikey_battle_alert(v_b.player_b, 'end:' || p_battle, 'You won the battle',
        'You beat ' || coalesce(v_name_a, 'your rival') || ' ' || v_b.wins_b || '-' || v_b.wins_a);
      perform spikey_battle_alert(v_b.player_a, 'end:' || p_battle, 'Battle over',
        coalesce(v_name_b, 'Your rival') || ' won ' || v_b.wins_b || '-' || v_b.wins_a || '. Rematch?');
    end if;
  end if;
  perform spikey_battle_ended(p_battle);
end
$$;

-- Decides a round once both of its runs are known, then the battle when
-- someone reached first_to wins (or the last round is played).
create or replace function public.spikey_battle_settle(p_battle bigint, p_number integer) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_b battles;
  v_r battle_rounds;
  v_a record;
  v_bb record;
  v_winner uuid;
begin
  select * into v_b from battles where id = p_battle for update;
  if not found or v_b.status not in ('waiting', 'open') then
    return;
  end if;
  select * into v_r from battle_rounds where battle = p_battle and number = p_number;
  if not found or v_r.settled then
    return;
  end if;
  select * into v_a from spikey_battle_side(v_r.run_a, v_r.lost_a);
  select * into v_bb from spikey_battle_side(v_r.run_b, v_r.lost_b);
  if not v_a.known or not v_bb.known then
    return;
  end if;
  if v_a.score > v_bb.score or (v_a.score = v_bb.score and v_a.coins > v_bb.coins) then
    v_winner := v_b.player_a;
  elsif v_bb.score > v_a.score or (v_a.score = v_bb.score and v_bb.coins > v_a.coins) then
    v_winner := v_b.player_b;
  end if;
  update battle_rounds set settled = true, winner = v_winner
  where battle = p_battle and number = p_number;
  update battles
  set wins_a = wins_a + case when v_winner = v_b.player_a then 1 else 0 end,
      wins_b = wins_b + case when v_winner = v_b.player_b then 1 else 0 end
  where id = p_battle
  returning * into v_b;
  if v_b.wins_a >= v_b.first_to then
    perform spikey_battle_end(p_battle, 'finished', 'played', v_b.player_a);
  elsif v_b.wins_b >= v_b.first_to then
    perform spikey_battle_end(p_battle, 'finished', 'played', v_b.player_b);
  elsif p_number >= (spikey_battle_limits() ->> 'max_rounds')::integer then
    perform spikey_battle_end(
      p_battle, 'finished', 'played',
      case when v_b.wins_a > v_b.wins_b then v_b.player_a
           when v_b.wins_b > v_b.wins_a then v_b.player_b end
    );
  else
    perform spikey_battle_refresh(p_battle);
  end if;
end
$$;

-- The checker marked runs: decide the rounds they belong to. Never fails the
-- checker's work.
create or replace function public.spikey_battle_runs_checked() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v record;
begin
  for v in
    select distinct r.battle, r.number
    from changed c
    join battle_rounds r on r.run_a = c.id or r.run_b = c.id
    where c.board = 'battle' and c.status <> 'pending'
  loop
    begin
      perform spikey_battle_settle(v.battle, v.number);
    exception when others then
      null;
    end;
  end loop;
  return null;
end
$$;

drop trigger if exists runs_battle_settle on public.runs;
create trigger runs_battle_settle
  after update on public.runs
  referencing new table as changed
  for each statement execute function public.spikey_battle_runs_checked();

-- A battle as one player sees it.
create or replace function public.spikey_battle_view(p_battle bigint, p_me uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_b battles;
  v_them uuid;
  v_mine_a boolean;
  v_next record;
  v_rounds jsonb;
  v_play jsonb;
  v_r battle_rounds;
  v_rival runs;
  v_rival_run bigint;
  v_opp players;
  v_close_days integer := (spikey_battle_limits() ->> 'close_after_days')::integer;
begin
  select * into v_b from battles where id = p_battle;
  if not found or (v_b.player_a <> p_me and v_b.player_b is distinct from p_me) then
    raise exception 'unknown battle';
  end if;
  v_mine_a := v_b.player_a = p_me;
  v_them := case when v_mine_a then v_b.player_b else v_b.player_a end;
  select * into v_opp from players where id = v_them;
  select coalesce(jsonb_agg(jsonb_build_object(
    'number', x.number,
    'blind', x.blind,
    'mine_first', x.first_player = p_me,
    'my_score', x.my_score,
    'their_score', case when x.my_known or not x.blind then x.their_score end,
    'winner', case when not x.settled then null
                   when x.winner is null then 'draw'
                   when x.winner = p_me then 'me' else 'them' end
  ) order by x.number), '[]'::jsonb) into v_rounds
  from (
    select r.*,
      (case when v_mine_a then sa.score else sb.score end) as my_score,
      (case when v_mine_a then sa.known else sb.known end) as my_known,
      (case when v_mine_a then sb.score else sa.score end) as their_score
    from battle_rounds r,
      lateral spikey_battle_side(r.run_a, r.lost_a) sa,
      lateral spikey_battle_side(r.run_b, r.lost_b) sb
    where r.battle = p_battle
  ) x;
  select * into v_next from spikey_battle_next(p_battle, p_me) limit 1;
  if v_next.number is not null then
    v_play := jsonb_build_object('round', v_next.number, 'role', v_next.role);
    if v_next.role = 'answer' then
      select * into v_r from battle_rounds where battle = p_battle and number = v_next.number;
      v_rival_run := case when v_mine_a then v_r.run_b else v_r.run_a end;
      v_play := v_play || jsonb_build_object('blind', v_r.blind);
      if not v_r.blind and v_rival_run is not null then
        select * into v_rival from runs where id = v_rival_run;
        if v_rival.status = 'ok' then
          v_play := v_play || jsonb_build_object('rival', jsonb_build_object(
            'score', v_rival.score, 'coins', coalesce(v_rival.coins, 0), 'taps', v_rival.taps,
            'end_tick', v_rival.end_tick, 'seed', v_rival.seed, 'season', v_rival.season,
            'loadout', v_rival.loadout, 'gameplay_version', v_rival.gameplay_version
          ));
        elsif v_rival.status = 'pending' then
          v_play := v_play || jsonb_build_object('rival_pending', true);
        end if;
      end if;
    end if;
  end if;
  return jsonb_build_object(
    'battle', v_b.id,
    'status', v_b.status,
    'first_to', v_b.first_to,
    'random', v_b.random,
    'starter', v_mine_a,
    'wins_me', case when v_mine_a then v_b.wins_a else v_b.wins_b end,
    'wins_them', case when v_mine_a then v_b.wins_b else v_b.wins_a end,
    'turn', case when v_b.turn_player is null then null
                 when v_b.turn_player = p_me then 'me' else 'them' end,
    'opponent', case when v_opp.id is null then null else jsonb_build_object(
      'name', v_opp.name, 'flyer', v_opp.flyer, 'bot', v_opp.bot) end,
    'last_move_s', greatest(0, extract(epoch from now() - v_b.last_move_at)::bigint),
    'ended_by', v_b.ended_by,
    'winner', case when v_b.status <> 'finished' then null
                   when v_b.winner is null then 'draw'
                   when v_b.winner = p_me then 'me' else 'them' end,
    'can_close', v_b.status in ('waiting', 'open') and (
      v_b.player_b is null
      or (v_b.turn_player is distinct from p_me
          and (coalesce(v_opp.bot, false)
               or v_b.last_move_at < now() - make_interval(days => v_close_days)))),
    'can_nudge', v_b.status = 'open' and v_b.turn_player = v_them and not coalesce(v_opp.bot, false)
      and (v_b.nudged_at is null or v_b.nudged_at < now() - interval '1 day'),
    'rounds', v_rounds,
    'play', v_play
  );
end
$$;

create or replace function public.spikey_battle_mine(p_battle bigint) returns battles
language plpgsql security definer set search_path = public as $$
declare
  v_b battles;
begin
  select * into v_b from battles where id = p_battle for update;
  if not found or (v_b.player_a <> auth.uid() and v_b.player_b is distinct from auth.uid()) then
    raise exception 'unknown battle';
  end if;
  return v_b;
end
$$;

-- A new battle. 'invite': waits for a friend's code ('code' in the answer).
-- 'random': joins another player's waiting random battle when there is one,
-- else waits for someone. Either way round 1 can be played at once.
create or replace function public.battle_create(
  p_name text, p_flyer text, p_opponent text, p_gameplay_version integer
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_lim jsonb := spikey_battle_limits();
  v_b battles;
  v_code text;
begin
  perform spikey_ensure_player(p_name, p_flyer);
  if p_opponent not in ('invite', 'random') then
    raise exception 'unknown opponent';
  end if;
  if p_gameplay_version is null or p_gameplay_version < 1 then
    raise exception 'invalid gameplay_version';
  end if;
  if (select count(*) from battles
      where (player_a = v_uid or player_b = v_uid) and status in ('waiting', 'open'))
     >= (v_lim ->> 'open')::integer then
    raise exception 'too many battles';
  end if;
  if (select count(*) from battles where player_a = v_uid and created_at > now() - interval '1 day')
     >= (v_lim ->> 'creates_per_day')::integer then
    raise exception 'too many battles today';
  end if;
  if p_opponent = 'random' then
    select b.* into v_b from battles b
    join battle_rounds r on r.battle = b.id and r.number = 1
    join runs x on x.id = r.run_a and x.status = 'ok'
    where b.status = 'waiting' and b.random and b.player_b is null
      and b.player_a <> v_uid and b.gameplay_version = p_gameplay_version
      and not exists (
        select 1 from battles o
        where o.status in ('waiting', 'open')
          and ((o.player_a = v_uid and o.player_b = b.player_a)
            or (o.player_b = v_uid and o.player_a = b.player_a))
      )
    order by b.created_at
    limit 1
    for update of b skip locked;
    if found then
      update battles set player_b = v_uid, status = 'open', last_move_at = now(), reminded = 0
      where id = v_b.id;
      perform spikey_battle_refresh(v_b.id);
      perform spikey_battle_alert(v_b.player_a, 'joined:' || v_b.id, 'Battle on',
        coalesce((select name from players where id = v_uid), 'Someone') || ' took your battle');
      return spikey_battle_view(v_b.id, v_uid);
    end if;
    if (select count(*) from battles where player_a = v_uid and status = 'waiting' and random)
       >= (v_lim ->> 'random_waiting')::integer then
      raise exception 'too many random battles waiting';
    end if;
  end if;
  if p_opponent = 'invite' then
    v_code := spikey_battle_code();
  end if;
  insert into battles (player_a, random, invite_hash, first_to, gameplay_version, turn_player)
  values (
    v_uid, p_opponent = 'random',
    case when v_code is null then null else spikey_battle_code_hash(v_code) end,
    (v_lim ->> 'first_to')::integer, p_gameplay_version, v_uid
  )
  returning * into v_b;
  return spikey_battle_view(v_b.id, v_uid) || jsonb_build_object('code', v_code);
end
$$;

-- A friend's invite code.
create or replace function public.battle_join(p_code text, p_name text, p_flyer text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_b battles;
begin
  perform spikey_ensure_player(p_name, p_flyer);
  select * into v_b from battles where invite_hash = spikey_battle_code_hash(p_code) for update;
  if not found or v_b.status <> 'waiting' or v_b.created_at < now() - interval '7 days' then
    raise exception 'unknown code';
  end if;
  if v_b.player_a = v_uid then
    raise exception 'own battle';
  end if;
  if (select count(*) from battles
      where (player_a = v_uid or player_b = v_uid) and status in ('waiting', 'open'))
     >= (spikey_battle_limits() ->> 'open')::integer then
    raise exception 'too many battles';
  end if;
  update battles set player_b = v_uid, status = 'open', invite_hash = null,
         last_move_at = now(), reminded = 0
  where id = v_b.id;
  perform spikey_battle_refresh(v_b.id);
  perform spikey_battle_alert(v_b.player_a, 'joined:' || v_b.id, 'Battle on',
    coalesce((select name from players where id = v_uid), 'Your friend') || ' joined your battle');
  return spikey_battle_view(v_b.id, v_uid);
end
$$;

-- Your battles: open ones (your turn first), then finished ones of the last 30 days.
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
    where (b.player_a = v_uid or b.player_b = v_uid)
      and (b.status in ('waiting', 'open') or b.finished_at > now() - interval '30 days')
  ), '[]'::jsonb), 'limits', spikey_battle_limits());
end
$$;

create or replace function public.battle_get(p_battle bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  return spikey_battle_view(p_battle, auth.uid());
end
$$;

-- Starts a run: hands out the round's seed. One try: a run started before and
-- never sent (the phone was lost) now counts as 0, and the answer says so.
-- A round started on another gameplay version than this phone's is dealt
-- again for both (a new seed; the opener plays it again).
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
  if v_r.gameplay_version <> p_gameplay_version then
    -- Dealt again on the newer version: the opener plays it again.
    update battle_rounds
    set seed = spikey_battle_seed(), season = spikey_season_of(spikey_today()),
        gameplay_version = p_gameplay_version,
        run_a = null, run_b = null, started_a = null, started_b = null,
        lost_a = false, lost_b = false
    where battle = p_battle and number = p_round
    returning * into v_r;
    update battles set gameplay_version = greatest(gameplay_version, p_gameplay_version)
    where id = p_battle;
    perform spikey_battle_refresh(p_battle);
    if v_r.first_player <> v_uid then
      perform spikey_battle_alert(v_r.first_player, 'redeal:' || p_battle || ':' || p_round,
        'Round dealt again', 'A game update needs a new map for round ' || p_round || '. Your turn!');
      return spikey_battle_view(p_battle, v_uid) || jsonb_build_object('redealt', true);
    end if;
    select * into v_r from battle_rounds where battle = p_battle and number = p_round for update;
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

-- A finished run of a round. Sent twice (the answer was lost): the second
-- time changes nothing. A run that copies the rival's taps is rejected.
create or replace function public.battle_submit(
  p_battle bigint,
  p_round integer,
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
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_b battles;
  v_mine_a boolean;
  v_r battle_rounds;
  v_taps jsonb := coalesce(p_taps, '[]'::jsonb);
  v_loadout jsonb := '{}'::jsonb;
  v_rival_run bigint;
  v_copied boolean := false;
  v_run bigint;
  v_them uuid;
  v_turn uuid;
  v_name text;
begin
  perform spikey_ensure_player(p_name, p_flyer);
  v_b := spikey_battle_mine(p_battle);
  v_mine_a := v_b.player_a = v_uid;
  select * into v_r from battle_rounds where battle = p_battle and number = p_round for update;
  if not found then
    raise exception 'unknown round';
  end if;
  if (case when v_mine_a then v_r.run_a else v_r.run_b end) is not null
     or (case when v_mine_a then v_r.lost_a else v_r.lost_b end) then
    return spikey_battle_view(p_battle, v_uid);
  end if;
  if (case when v_mine_a then v_r.started_a else v_r.started_b end) is null then
    raise exception 'run not started';
  end if;
  if p_seed is distinct from v_r.seed or coalesce(p_season, -1) <> v_r.season
     or p_gameplay_version is distinct from v_r.gameplay_version then
    raise exception 'not that round''s map';
  end if;
  if jsonb_typeof(v_taps) <> 'array' or jsonb_array_length(v_taps) > 20000 then
    raise exception 'invalid taps';
  end if;
  if p_loadout is not null and jsonb_typeof(p_loadout) = 'object'
     and length(p_loadout::text) <= 1024 then
    v_loadout := p_loadout;
  end if;
  v_rival_run := case when v_mine_a then v_r.run_b else v_r.run_a end;
  if v_rival_run is not null then
    v_copied := spikey_taps_copied(v_taps, (select taps from runs where id = v_rival_run));
  end if;
  insert into runs (
    player_id, score, day, played_at, gameplay_version, seed, taps, loadout,
    season, coins, end_tick, revives, board, status, reason, checked_at
  )
  values (
    v_uid, greatest(0, least(coalesce(p_score, 0), 100000)), spikey_today(), now(),
    p_gameplay_version, v_r.seed, v_taps, v_loadout, v_r.season,
    case when p_coins between 0 and 100000 then p_coins end,
    case when p_end_tick between 0 and 10000000 then p_end_tick end,
    '[]'::jsonb, 'battle',
    case when v_copied then 'rejected' else 'pending' end,
    case when v_copied then 'copied the rival''s taps' else '' end,
    case when v_copied then now() end
  )
  returning id into v_run;
  if v_mine_a then
    update battle_rounds set run_a = v_run where battle = p_battle and number = p_round;
  else
    update battle_rounds set run_b = v_run where battle = p_battle and number = p_round;
  end if;
  update battles set last_move_at = now(), reminded = 0 where id = p_battle;
  perform spikey_battle_settle(p_battle, p_round);
  v_turn := spikey_battle_refresh(p_battle);
  v_them := case when v_mine_a then v_b.player_b else v_b.player_a end;
  if v_turn is not null and v_turn = v_them then
    select name into v_name from players where id = v_uid;
    perform spikey_battle_alert(v_them, 'turn:' || p_battle || ':' || p_round, 'Your turn!',
      coalesce(v_name, 'Your rival') || ' played round ' || p_round || '. Your turn!');
  end if;
  return spikey_battle_view(p_battle, v_uid);
end
$$;

-- Gives up: the other player wins.
create or replace function public.battle_resign(p_battle bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_b battles := spikey_battle_mine(p_battle);
  v_them uuid := case when v_b.player_a = auth.uid() then v_b.player_b else v_b.player_a end;
  v_name text;
begin
  if v_b.status not in ('waiting', 'open') then
    raise exception 'battle over';
  end if;
  if v_them is null then
    -- Nobody joined yet: nothing to win, so it just closes.
    perform spikey_battle_end(p_battle, 'closed', 'closed', null);
  else
    perform spikey_battle_end(p_battle, 'finished', 'resigned', v_them);
    select name into v_name from players where id = auth.uid();
    perform spikey_battle_alert(v_them, 'resigned:' || p_battle, 'You won the battle',
      coalesce(v_name, 'Your rival') || ' resigned. You win the battle');
  end if;
  return spikey_battle_view(p_battle, auth.uid());
end
$$;

-- Ends a battle with no result, after 7 days waiting on the other player (at
-- once when nobody joined yet, or the other player is a bot).
create or replace function public.battle_close(p_battle bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_b battles := spikey_battle_mine(p_battle);
  v_ok boolean;
begin
  v_ok := (spikey_battle_view(p_battle, auth.uid()) ->> 'can_close')::boolean;
  if not coalesce(v_ok, false) then
    raise exception 'can''t close yet';
  end if;
  perform spikey_battle_end(p_battle, 'closed', 'closed', null);
  return spikey_battle_view(p_battle, auth.uid());
end
$$;

-- Once a day: a push to the player whose turn it is.
create or replace function public.battle_nudge(p_battle bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_b battles := spikey_battle_mine(p_battle);
  v_name text;
begin
  if not coalesce((spikey_battle_view(p_battle, auth.uid()) ->> 'can_nudge')::boolean, false) then
    raise exception 'can''t nudge now';
  end if;
  update battles set nudged_at = now() where id = p_battle;
  select name into v_name from players where id = auth.uid();
  perform spikey_battle_alert(v_b.turn_player, 'nudge:' || p_battle || ':' || spikey_today(),
    coalesce(v_name, 'Your rival') || ' nudged you', 'Your turn in the battle');
  return spikey_battle_view(p_battle, auth.uid());
end
$$;

-- The same two players again; the one who asks opens round 1.
create or replace function public.battle_rematch(p_battle bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_b battles := spikey_battle_mine(p_battle);
  v_them uuid := case when v_b.player_a = v_uid then v_b.player_b else v_b.player_a end;
  v_new battles;
begin
  if v_b.status not in ('finished', 'closed') or v_them is null then
    raise exception 'no rematch';
  end if;
  if (select count(*) from battles
      where (player_a = v_uid or player_b = v_uid) and status in ('waiting', 'open'))
     >= (spikey_battle_limits() ->> 'open')::integer then
    raise exception 'too many battles';
  end if;
  insert into battles (player_a, player_b, random, status, first_to, gameplay_version, turn_player)
  values (v_uid, v_them, v_b.random, 'open', v_b.first_to, v_b.gameplay_version, v_uid)
  returning * into v_new;
  perform spikey_battle_alert(v_them, 'rematch:' || v_new.id, 'Rematch',
    coalesce((select name from players where id = v_uid), 'Your rival') || ' wants a rematch');
  return spikey_battle_view(v_new.id, v_uid);
end
$$;

-- Nudges for battles nobody moved in: after 1 day and after 3 days, then no
-- more. Never between 22:00 and 08:00 on the player's phone clock: those wait
-- for the morning. Called by the server every few minutes. Returns how many.
create or replace function public.spikey_battle_reminders() returns integer
language plpgsql security definer set search_path = public as $$
declare
  v record;
  v_n integer := 0;
  v_hour integer;
begin
  for v in
    select b.*, d.utc_offset_min, o.name as other_name
    from battles b
    left join push_devices d on d.player_id = b.turn_player and d.enabled
    left join players o on o.id = case when b.turn_player = b.player_a then b.player_b else b.player_a end
    where b.status = 'open' and b.turn_player is not null
      and ((b.reminded = 0 and b.last_move_at < now() - interval '1 day')
        or (b.reminded = 1 and b.last_move_at < now() - interval '3 days'))
    for update of b skip locked
  loop
    v_hour := extract(hour from (now() at time zone 'UTC') + make_interval(mins => coalesce(v.utc_offset_min, 60)));
    if v_hour < 8 or v_hour >= 22 then
      continue;
    end if;
    update battles set reminded = reminded + 1 where id = v.id;
    perform spikey_battle_alert(v.turn_player, 'remind:' || v.id || ':' || (v.reminded + 1),
      'Your turn', coalesce(v.other_name, 'Your rival') || ' is waiting for your turn');
    v_n := v_n + 1;
  end loop;
  return v_n;
end
$$;

revoke all on function public.spikey_battle_limits() from public, anon;
revoke all on function public.spikey_battle_seed() from public, anon, authenticated;
revoke all on function public.spikey_battle_code() from public, anon, authenticated;
revoke all on function public.spikey_battle_code_hash(text) from public, anon, authenticated;
revoke all on function public.spikey_taps_copied(jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.spikey_battle_side(bigint, boolean) from public, anon, authenticated;
revoke all on function public.spikey_battle_next(bigint, uuid) from public, anon, authenticated;
revoke all on function public.spikey_battle_alert(uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.spikey_battle_refresh(bigint) from public, anon, authenticated;
revoke all on function public.spikey_battle_ended(bigint) from public, anon, authenticated;
revoke all on function public.spikey_battle_end(bigint, text, text, uuid) from public, anon, authenticated;
revoke all on function public.spikey_battle_settle(bigint, integer) from public, anon, authenticated;
revoke all on function public.spikey_battle_runs_checked() from public, anon, authenticated;
revoke all on function public.spikey_battle_view(bigint, uuid) from public, anon, authenticated;
revoke all on function public.spikey_battle_mine(bigint) from public, anon, authenticated;
revoke all on function public.spikey_battle_reminders() from public, anon, authenticated;
revoke all on function public.worker_pending_alerts(integer) from public, anon, authenticated;
revoke all on function public.worker_mark_alerts(jsonb) from public, anon, authenticated;
revoke all on function public.battle_create(text, text, text, integer) from public, anon;
revoke all on function public.battle_join(text, text, text) from public, anon;
revoke all on function public.battle_list() from public, anon;
revoke all on function public.battle_get(bigint) from public, anon;
revoke all on function public.battle_start_run(bigint, integer, integer) from public, anon;
revoke all on function public.battle_submit(
  bigint, integer, text, text, integer, integer, bigint, jsonb, jsonb, integer, integer, integer
) from public, anon;
revoke all on function public.battle_resign(bigint) from public, anon;
revoke all on function public.battle_close(bigint) from public, anon;
revoke all on function public.battle_nudge(bigint) from public, anon;
revoke all on function public.battle_rematch(bigint) from public, anon;
grant execute on function public.battle_create(text, text, text, integer) to authenticated;
grant execute on function public.battle_join(text, text, text) to authenticated;
grant execute on function public.battle_list() to authenticated;
grant execute on function public.battle_get(bigint) to authenticated;
grant execute on function public.battle_start_run(bigint, integer, integer) to authenticated;
grant execute on function public.battle_submit(
  bigint, integer, text, text, integer, integer, bigint, jsonb, jsonb, integer, integer, integer
) to authenticated;
grant execute on function public.battle_resign(bigint) to authenticated;
grant execute on function public.battle_close(bigint) to authenticated;
grant execute on function public.battle_nudge(bigint) to authenticated;
grant execute on function public.battle_rematch(bigint) to authenticated;
