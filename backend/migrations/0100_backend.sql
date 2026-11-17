-- The server's own tables, next to the game's (public, the timestamped migrations).
-- Sign-in: device keys and sessions, kept only as sha-256 hashes. Phone
-- transfers: one-time codes (docs/ACCOUNT_TRANSFER.md). The replay check: runs
-- the Rust check rejected wait here for headless Godot's word (godot_queue).
create schema if not exists backend;

-- A phone's device key ("Fj-" + 64 hex), which signs it in as its player after
-- a reinstall. Revoked when a transfer moved the player to another phone.
create table if not exists backend.devices (
  key_hash bytea primary key,
  player_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_reason text
);
create index if not exists devices_player on backend.devices (player_id);

-- One signed-in phone: a short access token and a refresh token that changes
-- each time it is used.
create table if not exists backend.sessions (
  id bigint generated always as identity primary key,
  player_id uuid not null references auth.users (id) on delete cascade,
  access_hash bytea not null unique,
  access_expires timestamptz not null,
  refresh_hash bytea not null unique,
  refresh_expires timestamptz not null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_reason text
);
create index if not exists sessions_player on backend.sessions (player_id);

-- Move to a new phone: the code itself is never stored, only its hash.
create table if not exists backend.transfer_codes (
  code_hash bytea primary key,
  player_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz,
  used_by_player uuid,
  used_by_ip text,
  cancelled_at timestamptz
);
create index if not exists transfer_codes_player on backend.transfer_codes (player_id, created_at);

-- Who moved when: what happened when a player says "my progress is gone".
create table if not exists backend.transfer_log (
  id bigint generated always as identity primary key,
  player_id uuid not null,
  left_behind uuid,
  ip text,
  at timestamptz not null default now()
);

-- Runs the Rust check rejected: final only once headless Godot agrees
-- (the godot-check CronJob, docs/SERVER_MIGRATION.md).
create table if not exists backend.godot_queue (
  run_id bigint primary key references public.runs (id) on delete cascade,
  rust_reason text not null,
  queued_at timestamptz not null default now()
);

-- What a transfer code would move, for the confirm screen: name, best checked
-- score, gold and items in the server's save, diamonds.
create or replace function backend.transfer_summary(p_player uuid) returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'name', coalesce((select name from public.players where id = p_player), ''),
    'best', coalesce((
      select max(score) from public.runs where player_id = p_player and status = 'ok'
    ), 0),
    'gold', coalesce((
      select (data ->> 'coins')::integer from public.profiles where player_id = p_player
    ), 0),
    'items', coalesce((
      select sum(jsonb_array_length(v))::integer
      from public.profiles p, jsonb_each(p.data -> 'owned') as o(k, v)
      where p.player_id = p_player and jsonb_typeof(v) = 'array'
    ), 0),
    'diamonds', coalesce((
      select diamonds from public.wallets where player_id = p_player
    ), 0)
  )
$$;

-- The caller's own runs, newest first, for Your runs on a phone the player just
-- moved to ({"runs": [...]}). Rejected runs are left out.
create or replace function public.get_my_runs(p_limit integer default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;
  return jsonb_build_object('runs', coalesce((
    select jsonb_agg(jsonb_build_object(
      'run', r.id, 'score', r.score, 'gameplay_version', r.gameplay_version,
      'seed', r.seed, 'season', r.season, 'taps', r.taps, 'revives', r.revives,
      'coins', r.coins, 'end_tick', r.end_tick, 'loadout', r.loadout,
      'board', r.board, 'played_at', extract(epoch from r.played_at)::bigint
    ) order by r.id desc)
    from (
      select * from runs
      where player_id = v_uid and status <> 'rejected'
      order by id desc
      limit greatest(1, least(coalesce(p_limit, 50), 200))
    ) r
  ), '[]'::jsonb));
end
$$;

-- Pending runs for headless Godot: the ones the Rust check rejected.
create or replace function backend.godot_pending_runs(p_limit integer default 200) returns jsonb
language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r.id, 'gameplay_version', r.gameplay_version, 'seed', r.seed,
    'season', r.season, 'taps', r.taps, 'revives', r.revives, 'score', r.score,
    'coins', r.coins, 'end_tick', r.end_tick, 'day', r.day
  ) order by r.id), '[]'::jsonb)
  from (
    select runs.* from backend.godot_queue q join public.runs on runs.id = q.run_id
    where runs.status = 'pending'
    order by q.run_id
    limit greatest(1, least(coalesce(p_limit, 200), 1000))
  ) r
$$;

-- Godot's verdicts: written like the checker's, then the queue entries go.
create or replace function backend.godot_record_results(p_results jsonb) returns integer
language plpgsql as $$
declare
  v_count integer;
begin
  v_count := public.worker_record_results(p_results);
  delete from backend.godot_queue q
  using jsonb_to_recordset(p_results) as x(id bigint, status text, reason text)
  where q.run_id = x.id;
  return v_count;
end
$$;
