-- The player's save on the server, so a reinstall (or a restored phone) gets
-- its flyers, hats, worlds, gold, best score and rooms back.
--
--   profiles   one row per player: the save as the game wrote it (the part
--              that belongs to the player, not to the phone; see
--              Profile.cloud_dict() in meta/profile.gd) and a revision that
--              goes up by one with every save.
--
-- The server doesn't merge: a save names the revision it was based on, and
-- only a save based on the newest one is kept. Any other gets the newest one
-- back, the game merges the two (Profile.merge_cloud) and saves again. A new
-- phone of a player who already has a row (base 0) always gets it back first.
-- Diamonds are not in here: they live in wallets (20261110100000_diamonds.sql).

create table if not exists public.profiles (
  player_id uuid primary key references auth.users (id) on delete cascade,
  data jsonb not null check (jsonb_typeof(data) = 'object'),
  revision bigint not null default 1 check (revision >= 1),
  updated_at timestamptz not null default now()
);

-- No policies: the game can't read or write the table directly.
alter table public.profiles enable row level security;

-- Saves this player's profile when p_base is the newest revision (0: the
-- phone never had one). Answers {"status": "saved", "revision": n}, or
-- {"status": "conflict", "revision": n, "data": {...}} with the newest save.
create or replace function public.sync_profile(p_data jsonb, p_base bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_row profiles%rowtype;
begin
  if v_me is null then
    raise exception 'not signed in';
  end if;
  if p_data is null or jsonb_typeof(p_data) <> 'object' then
    raise exception 'invalid profile';
  end if;
  if octet_length(p_data::text) > 65536 then
    raise exception 'profile too large';
  end if;
  insert into profiles (player_id, data) values (v_me, p_data)
  on conflict (player_id) do nothing;
  if found then
    return jsonb_build_object('status', 'saved', 'revision', 1);
  end if;
  select * into v_row from profiles where player_id = v_me for update;
  if coalesce(p_base, 0) <> v_row.revision then
    return jsonb_build_object(
      'status', 'conflict', 'revision', v_row.revision, 'data', v_row.data
    );
  end if;
  update profiles
  set data = p_data, revision = revision + 1, updated_at = now()
  where player_id = v_me
  returning * into v_row;
  return jsonb_build_object('status', 'saved', 'revision', v_row.revision);
end $$;

revoke all on function public.sync_profile(jsonb, bigint) from public, anon;
grant execute on function public.sync_profile(jsonb, bigint) to authenticated;
