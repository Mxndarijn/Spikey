-- Premium items (sold for diamonds) count only when the server sold them.
-- A phone's save can be edited to own anything, but what other players see
-- comes from here: a run's loadout (board plates, replays) and the flyer on
-- the boards keep a premium item only when this player bought it with
-- diamonds, which diamond_ledger records ('item', ref "kind:id", see
-- spend_diamonds). Otherwise the item is dropped (the default look shows).
-- The game also gets the list back with every save sync (sync_profile), so a
-- reinstall gets its bought items back even without the old save.
--
--   premium_items   "kind:id" of every item with a diamond price. Must match
--                   Shop.diamond_price() in game/cosmetics/shop.gd
--                   (tests/unit/test_paid_items.gd checks it). A new premium
--                   item needs a new migration that adds its row.

create table if not exists public.premium_items (
  ref text primary key check (ref ~ '^[a-z]+:[a-z0-9_]+$')
);

alter table public.premium_items enable row level security;

insert into public.premium_items (ref) values
  ('flyer:bolt'),
  ('flyer:nova'),
  ('world:neon'),
  ('world:haunted'),
  ('world:winterfest'),
  ('world:glade'),
  ('world:aurora'),
  ('world:lantern')
on conflict (ref) do nothing;

-- The premium items this player bought ("kind:id"), oldest first.
create or replace function public.spikey_paid_items(p_player uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(ref order by first_id), '[]'::jsonb)
  from (
    select ref, min(id) as first_id
    from diamond_ledger
    where player_id = p_player and reason = 'item' and amount < 0 and ref <> ''
    group by ref
  ) bought
$$;

-- Whether the player may show "kind:id": anything not premium, or bought.
create or replace function public.spikey_may_show(p_player uuid, p_ref text) returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from premium_items where ref = p_ref)
    or exists (
      select 1 from diamond_ledger
      where player_id = p_player and reason = 'item' and amount < 0 and ref = p_ref
    )
$$;

-- A loadout ({"flyer": "bolt", "world": "ice", ...}) without the premium
-- items this player didn't buy.
create or replace function public.spikey_paid_loadout(p_player uuid, p_loadout jsonb)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
  from jsonb_each(coalesce(p_loadout, '{}'::jsonb))
  where jsonb_typeof(value) <> 'string'
    or spikey_may_show(p_player, key || ':' || (value #>> '{}'))
$$;

create or replace function public.spikey_runs_paid_loadout() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if jsonb_typeof(new.loadout) = 'object' then
    new.loadout := spikey_paid_loadout(new.player_id, new.loadout);
  end if;
  return new;
end $$;

drop trigger if exists runs_paid_loadout on public.runs;
create trigger runs_paid_loadout before insert or update of loadout on public.runs
for each row execute function public.spikey_runs_paid_loadout();

-- The flyer on the boards: an unbought premium one shows as the default.
create or replace function public.spikey_players_paid_flyer() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not spikey_may_show(new.id, 'flyer:' || new.flyer) then
    new.flyer := 'buzz';
  end if;
  return new;
end $$;

drop trigger if exists players_paid_flyer on public.players;
create trigger players_paid_flyer before insert or update of flyer on public.players
for each row execute function public.spikey_players_paid_flyer();

revoke all on function public.spikey_paid_items(uuid) from public, anon, authenticated;
revoke all on function public.spikey_may_show(uuid, text) from public, anon, authenticated;
revoke all on function public.spikey_paid_loadout(uuid, jsonb) from public, anon, authenticated;

-- Gold: the phone keeps it, but the server knows the most a player could
-- have: the gold of their runs that were not rejected, plus diamonds turned
-- into gold (Economy.GOLD_PER_DIAMOND = 100 each). gold_excess is how far a
-- synced save goes over that (0: fine). It is only a flag for a look in the
-- dashboard, never a cap: runs sent before runs had gold, or still waiting
-- on a phone, can make an honest save go over.
alter table public.profiles add column if not exists gold_excess bigint not null default 0;

create or replace function public.spikey_gold_ceiling(p_player uuid) returns bigint
language sql stable security definer set search_path = public as $$
  select
    coalesce((
      select sum(coalesce(coins, 0)) from runs
      where player_id = p_player and status <> 'rejected'
    ), 0)
    + coalesce((
      select sum(-amount) * 100 from diamond_ledger
      where player_id = p_player and reason = 'convert' and amount < 0
    ), 0)
$$;

revoke all on function public.spikey_gold_ceiling(uuid) from public, anon, authenticated;

-- sync_profile as before (20261110150000_profiles.sql), and every answer
-- also carries "paid": the premium items this player bought. A save that was
-- kept gets its gold_excess.
create or replace function public.sync_profile(p_data jsonb, p_base bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_row profiles%rowtype;
  v_paid jsonb;
  v_coins bigint := 0;
  v_excess bigint;
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
  v_paid := spikey_paid_items(v_me);
  if jsonb_typeof(p_data -> 'coins') = 'number' then
    v_coins := least(greatest((p_data ->> 'coins')::numeric, 0), 1e15)::bigint;
  end if;
  v_excess := greatest(v_coins - spikey_gold_ceiling(v_me), 0);
  insert into profiles (player_id, data, gold_excess) values (v_me, p_data, v_excess)
  on conflict (player_id) do nothing;
  if found then
    return jsonb_build_object('status', 'saved', 'revision', 1, 'paid', v_paid);
  end if;
  select * into v_row from profiles where player_id = v_me for update;
  if coalesce(p_base, 0) <> v_row.revision then
    return jsonb_build_object(
      'status', 'conflict', 'revision', v_row.revision, 'data', v_row.data, 'paid', v_paid
    );
  end if;
  update profiles
  set data = p_data, revision = revision + 1, gold_excess = v_excess, updated_at = now()
  where player_id = v_me
  returning * into v_row;
  return jsonb_build_object('status', 'saved', 'revision', v_row.revision, 'paid', v_paid);
end $$;

revoke all on function public.sync_profile(jsonb, bigint) from public, anon;
grant execute on function public.sync_profile(jsonb, bigint) to authenticated;
