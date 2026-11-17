-- Bots kickstart Battle (docs/DUEL_MODE.md, section 6). A random battle no
-- person takes within the bot wait (worker_settings 'bot_wait_s', 600 to start;
-- below 0 means bots are off) gets a bot. Bots are players marked `bot`, with a
-- friendly name from a small pool and always the BOT pill in the game; they
-- play through the same battle_* operations as anyone (the battle-bot worker,
-- backend/src/bot.rs), 2 to 30 minutes after their turn starts. Their level
-- (1 beginner .. 8 beast) is hidden: it starts from the player's own scores and
-- moves a level after each battle that was not close.

insert into public.worker_settings (key, value) values ('bot_wait_s', '600')
on conflict (key) do nothing;

alter table public.battles add column if not exists bot_due_at timestamptz;
alter table public.battles add column if not exists bot_level integer check (bot_level between 1 and 8);
create index if not exists battles_bot_due on public.battles (bot_due_at) where bot_due_at is not null;

-- The level a player's bots play at, learned battle by battle.
create table if not exists public.battle_bot_skill (
  player_id uuid primary key references public.players (id) on delete cascade,
  level integer not null check (level between 1 and 8),
  updated_at timestamptz not null default now()
);
alter table public.battle_bot_skill enable row level security;

create or replace function public.spikey_bot_names() returns text[]
language sql immutable as $$
  select array['Pip', 'Juno', 'Milo', 'Kiki', 'Bram', 'Nova', 'Tess', 'Oli', 'Rumi', 'Zed', 'Lola', 'Finn']
$$;

-- The bot player for a battle: one per name, made the first time it plays.
create or replace function public.spikey_bot_player(p_battle bigint) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_names text[] := spikey_bot_names();
  v_name text := v_names[1 + (p_battle % array_length(v_names, 1))::integer];
  v_id uuid;
begin
  select id into v_id from players where bot and name = v_name order by id limit 1;
  if v_id is null then
    v_id := gen_random_uuid();
    insert into auth.users (id) values (v_id);
    insert into players (id, name, flyer, bot) values (v_id, v_name, 'buzz', true);
  end if;
  return v_id;
end
$$;

-- A first guess at a player's level: the median of their last 20 checked runs.
create or replace function public.spikey_bot_level_guess(p_player uuid) returns integer
language sql stable as $$
  select case
    when m is null or m < 20 then 1
    when m < 45 then 2
    when m < 80 then 3
    when m < 120 then 4
    when m < 180 then 5
    when m < 250 then 6
    when m < 500 then 7
    else 8 end
  from (
    select percentile_cont(0.5) within group (order by score) as m
    from (
      select score from public.runs where player_id = p_player and status = 'ok'
      order by id desc limit 20
    ) r
  ) x
$$;

create or replace function public.spikey_bot_level(p_player uuid) returns integer
language sql stable as $$
  select coalesce(
    (select level from public.battle_bot_skill where player_id = p_player),
    public.spikey_bot_level_guess(p_player)
  )
$$;

-- As in 0110_battles.sql, and when the turn passes to a bot it gets a time
-- to play: 2 to 30 minutes from now.
create or replace function public.spikey_battle_refresh(p_battle bigint) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_b battles;
  v_turn uuid;
  v_bot boolean;
begin
  select * into v_b from battles where id = p_battle;
  if v_b.status not in ('waiting', 'open') then
    update battles set turn_player = null, bot_due_at = null where id = p_battle;
    return null;
  end if;
  if exists (select 1 from spikey_battle_next(p_battle, v_b.player_a)) then
    v_turn := v_b.player_a;
  elsif v_b.player_b is not null and exists (select 1 from spikey_battle_next(p_battle, v_b.player_b)) then
    v_turn := v_b.player_b;
  end if;
  v_bot := v_turn is not null and exists (select 1 from players where id = v_turn and bot);
  update battles
  set turn_player = v_turn,
      bot_due_at = case
        when not v_bot then null
        when v_b.turn_player is not distinct from v_turn and v_b.bot_due_at is not null then v_b.bot_due_at
        else now() + make_interval(secs => 120 + floor(random() * 1680)) end
  where id = p_battle;
  return v_turn;
end
$$;

-- As in 0111_wins_boards.sql (the result for the boards), and a battle against
-- a bot teaches the player's bot level: a bot that won by 3 or more plays a
-- level weaker next time, one that lost by 3 or more a level stronger.
create or replace function public.spikey_battle_ended(p_battle bigint) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_b battles;
  v_c record;
  v_bot_a boolean;
  v_bot_b boolean;
  v_human uuid;
  v_margin integer;
  v_level integer;
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
  select bot into v_bot_a from players where id = v_b.player_a;
  select bot into v_bot_b from players where id = v_b.player_b;
  if v_b.ended_by <> 'played' or v_bot_a = v_bot_b then
    return;
  end if;
  v_human := case when v_bot_a then v_b.player_b else v_b.player_a end;
  -- The human's wins minus the bot's.
  v_margin := case when v_bot_a then v_b.wins_b - v_b.wins_a else v_b.wins_a - v_b.wins_b end;
  v_level := coalesce(v_b.bot_level, spikey_bot_level(v_human));
  if v_margin >= 3 then
    v_level := least(8, v_level + 1);
  elsif v_margin <= -3 then
    v_level := greatest(1, v_level - 1);
  end if;
  insert into battle_bot_skill (player_id, level) values (v_human, v_level)
  on conflict (player_id) do update set level = excluded.level, updated_at = now();
end
$$;

-- Random battles nobody took within the bot wait get a bot (oldest first).
-- Returns how many. Called by the battle-bot worker.
create or replace function public.worker_assign_bots(p_limit integer default 20) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_wait integer := coalesce((select value::integer from worker_settings where key = 'bot_wait_s'), 600);
  v record;
  v_bot uuid;
  v_n integer := 0;
begin
  if v_wait < 0 then
    return 0;
  end if;
  for v in
    select b.* from battles b
    join battle_rounds r on r.battle = b.id and r.number = 1
    join runs x on x.id = r.run_a and x.status = 'ok'
    where b.status = 'waiting' and b.random and b.player_b is null
      and x.checked_at < now() - make_interval(secs => v_wait)
    order by b.created_at
    limit greatest(1, least(coalesce(p_limit, 20), 200))
    for update of b skip locked
  loop
    v_bot := spikey_bot_player(v.id);
    update battles
    set player_b = v_bot, status = 'open', bot_level = spikey_bot_level(v.player_a),
        last_move_at = now(), reminded = 0
    where id = v.id;
    perform spikey_battle_refresh(v.id);
    perform spikey_battle_alert(v.player_a, 'joined:' || v.id, 'Battle on',
      (select name from players where id = v_bot) || ' (a bot) took your battle');
    v_n := v_n + 1;
  end loop;
  return v_n;
end
$$;

-- The bot turns due now: [{"battle": 12, "bot": "<uuid>", "level": 3}].
create or replace function public.worker_bot_turns(p_limit integer default 20) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'battle', b.id, 'bot', b.turn_player, 'level', coalesce(b.bot_level, 3)
  ) order by b.bot_due_at), '[]'::jsonb)
  from (
    select * from battles
    where status = 'open' and bot_due_at is not null and bot_due_at <= now()
    order by bot_due_at
    limit greatest(1, least(coalesce(p_limit, 20), 200))
  ) b
$$;

-- An admin's switch for phase c: the bot wait in seconds (below 0: bots off).
create or replace function public.worker_set_bot_wait(p_seconds integer) returns void
language sql security definer set search_path = public as $$
  insert into worker_settings (key, value) values ('bot_wait_s', p_seconds::text)
  on conflict (key) do update set value = excluded.value
$$;

revoke all on function public.spikey_bot_names() from public, anon, authenticated;
revoke all on function public.spikey_bot_player(bigint) from public, anon, authenticated;
revoke all on function public.spikey_bot_level_guess(uuid) from public, anon, authenticated;
revoke all on function public.spikey_bot_level(uuid) from public, anon, authenticated;
revoke all on function public.worker_assign_bots(integer) from public, anon, authenticated;
revoke all on function public.worker_bot_turns(integer) from public, anon, authenticated;
revoke all on function public.worker_set_bot_wait(integer) from public, anon, authenticated;
