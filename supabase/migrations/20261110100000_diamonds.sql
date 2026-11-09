-- Diamonds live on the server. A phone's save file can be edited; this
-- balance cannot: the game only reaches it through the functions below.
--
--   wallets          one row per player: the diamond balance (never below 0).
--   diamond_ledger   every change to a balance, with its reason, for support
--                    and for store reports.
--   daily_prizes     who finished in the top 10 of a finished day, and whether
--                    the prize was claimed yet.
--   settled_days     days whose prizes were handed out (each day pays once).
--   bonus_prizes     prizes everyone can reach: a best score of 25, 50, 75 or
--                    100 for the first time (1, 1, 2, 3 diamonds, once each)
--                    and a checked run on 7 days in a row (1 diamond per 7).
--
-- Daily prizes: 1st 3 diamonds, 2nd and 3rd 2, 4th to 10th 1 (meta/economy.gd
-- holds the same table for the game's own screens). A day is the same
-- Europe/Amsterdam day the Daily board uses. Only checked ("ok") runs count,
-- one per player (their best); on a tie the earlier run takes the higher place.
-- There is no timer: a finished day is paid out the first time anyone asks for
-- their wallet after it ended and after the checker went over its runs.

create table if not exists public.wallets (
  player_id uuid primary key references public.players (id) on delete cascade,
  diamonds integer not null default 0 check (diamonds >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.diamond_ledger (
  id bigint generated always as identity primary key,
  player_id uuid not null references public.players (id) on delete cascade,
  amount integer not null check (amount <> 0),
  reason text not null check (
    reason in ('daily_prize', 'milestone', 'streak', 'pack', 'convert', 'item')
  ),
  ref text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists diamond_ledger_player on public.diamond_ledger (player_id, id);

create table if not exists public.daily_prizes (
  day date not null,
  player_id uuid not null references public.players (id) on delete cascade,
  rank integer not null check (rank between 1 and 10),
  score integer not null,
  diamonds integer not null check (diamonds > 0),
  claimed_at timestamptz,
  primary key (day, player_id)
);

create index if not exists daily_prizes_unclaimed on public.daily_prizes (player_id)
  where claimed_at is null;

create table if not exists public.settled_days (
  day date primary key,
  settled_at timestamptz not null default now()
);

create table if not exists public.bonus_prizes (
  player_id uuid not null references public.players (id) on delete cascade,
  kind text not null check (kind in ('milestone', 'streak')),
  -- milestone: the score reached ("50"); streak: the streak's 7th, 14th... day.
  ref text not null,
  diamonds integer not null check (diamonds > 0),
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  primary key (player_id, kind, ref)
);

create index if not exists bonus_prizes_unclaimed on public.bonus_prizes (player_id)
  where claimed_at is null;

-- No policies: the game can't read or write these tables directly.
alter table public.bonus_prizes enable row level security;
alter table public.wallets enable row level security;
alter table public.diamond_ledger enable row level security;
alter table public.daily_prizes enable row level security;
alter table public.settled_days enable row level security;

-- Diamonds for a place on the daily board (0 outside the top 10).
create or replace function public.spikey_daily_prize(p_rank integer) returns integer
language sql immutable as $$
  select case
    when p_rank = 1 then 3
    when p_rank in (2, 3) then 2
    when p_rank between 4 and 10 then 1
    else 0
  end
$$;

-- Adds to (or takes from) a player's balance and writes the ledger line.
-- Returns the new balance; raises when the balance would go below zero.
create or replace function public.spikey_change_diamonds(
  p_player uuid,
  p_amount integer,
  p_reason text,
  p_ref text
) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_new integer;
begin
  if p_amount is null or p_amount = 0 then
    raise exception 'invalid amount';
  end if;
  -- A phone that never sent a run or picked a name has no player row, and so
  -- no diamonds.
  if not exists (select 1 from players where id = p_player) then
    raise exception 'not enough diamonds';
  end if;
  insert into wallets (player_id) values (p_player) on conflict (player_id) do nothing;
  update wallets
  set diamonds = diamonds + p_amount, updated_at = now()
  where player_id = p_player and diamonds + p_amount >= 0
  returning diamonds into v_new;
  if v_new is null then
    raise exception 'not enough diamonds';
  end if;
  insert into diamond_ledger (player_id, amount, reason, ref)
  values (p_player, p_amount, p_reason, left(coalesce(p_ref, ''), 64));
  return v_new;
end
$$;

-- Hands out the prizes of finished days that were not paid yet (the last 7
-- days only). Yesterday waits while any of its runs still waits for the
-- checker; older days no longer wait, so one stuck run can't hold prizes back.
-- A run that arrives after its day was settled (played offline) wins nothing.
create or replace function public.spikey_settle_days() returns void
language plpgsql security definer set search_path = public as $$
declare
  v_today date := spikey_today();
  v_day date;
begin
  for v_day in
    select distinct r.day
    from runs r
    where r.day < v_today
      and r.day >= v_today - 7
      and not exists (select 1 from settled_days s where s.day = r.day)
    order by r.day
  loop
    if v_day >= v_today - 1
       and exists (select 1 from runs r where r.day = v_day and r.status = 'pending') then
      continue;
    end if;
    -- Two phones asking at once: only the one that inserts this row pays.
    insert into settled_days (day) values (v_day) on conflict (day) do nothing;
    if not found then
      continue;
    end if;
    insert into daily_prizes (day, player_id, rank, score, diamonds)
    select v_day, t.player_id, t.place, t.score, spikey_daily_prize(t.place)
    from (
      select b.player_id, b.score,
             (row_number() over (order by b.score desc, b.played_at asc, b.run_id asc))::integer
               as place
      from (
        select distinct on (r.player_id) r.player_id, r.score, r.played_at, r.id as run_id
        from runs r
        where r.day = v_day and r.status = 'ok'
        order by r.player_id, r.score desc, r.played_at asc
      ) b
    ) t
    where t.place <= 10
    on conflict (day, player_id) do nothing;
  end loop;
end
$$;

-- Writes the bonus prizes a player has earned and does not have yet. Only
-- checked runs count. Safe to call again and again: each prize has one row.
create or replace function public.spikey_award_bonuses(p_player uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_best integer;
begin
  select max(r.score) into v_best
  from runs r
  where r.player_id = p_player and r.status = 'ok';
  if v_best is null then
    return;
  end if;
  insert into bonus_prizes (player_id, kind, ref, diamonds)
  select p_player, 'milestone', m.score::text, m.diamonds
  from (values (25, 1), (50, 1), (75, 2), (100, 3)) as m(score, diamonds)
  where v_best >= m.score
  on conflict (player_id, kind, ref) do nothing;
  -- The player's latest unbroken row of days with a checked run: one prize
  -- for its 7th day, one for its 14th, and so on.
  with days as (
    select distinct r.day
    from runs r
    where r.player_id = p_player and r.status = 'ok' and r.day > spikey_today() - 400
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

-- The caller's balance and the prizes they have not claimed yet:
-- {"diamonds": 7,
--  "prizes": [{"day": "2026-11-09", "rank": 2, "score": 87, "diamonds": 2}],
--  "bonuses": [{"kind": "milestone", "ref": "50", "diamonds": 1}]}
create or replace function public.get_wallet() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;
  perform spikey_settle_days();
  perform spikey_award_bonuses(v_uid);
  return jsonb_build_object(
    'diamonds', coalesce((select w.diamonds from wallets w where w.player_id = v_uid), 0),
    'bonuses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'kind', b.kind, 'ref', b.ref, 'diamonds', b.diamonds
      ) order by b.created_at, b.kind, b.ref)
      from bonus_prizes b
      where b.player_id = v_uid and b.claimed_at is null
    ), '[]'::jsonb),
    'prizes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'day', p.day, 'rank', p.rank, 'score', p.score, 'diamonds', p.diamonds
      ) order by p.day)
      from daily_prizes p
      where p.player_id = v_uid and p.claimed_at is null
    ), '[]'::jsonb)
  );
end
$$;

-- Claims every unclaimed prize of the caller, daily ones and bonuses:
-- {"diamonds": new balance, "claimed": diamonds just added}. Claiming twice
-- adds nothing the second time.
create or replace function public.claim_prizes() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_prize record;
  v_claimed integer := 0;
  v_balance integer;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;
  perform spikey_settle_days();
  perform spikey_award_bonuses(v_uid);
  for v_prize in
    update daily_prizes
    set claimed_at = now()
    where player_id = v_uid and claimed_at is null
    returning day, diamonds
  loop
    v_balance := spikey_change_diamonds(
      v_uid, v_prize.diamonds, 'daily_prize', v_prize.day::text
    );
    v_claimed := v_claimed + v_prize.diamonds;
  end loop;
  for v_prize in
    update bonus_prizes
    set claimed_at = now()
    where player_id = v_uid and claimed_at is null
    returning kind, ref, diamonds
  loop
    v_balance := spikey_change_diamonds(v_uid, v_prize.diamonds, v_prize.kind, v_prize.ref);
    v_claimed := v_claimed + v_prize.diamonds;
  end loop;
  if v_balance is null then
    v_balance := coalesce((select w.diamonds from wallets w where w.player_id = v_uid), 0);
  end if;
  return jsonb_build_object('diamonds', v_balance, 'claimed', v_claimed);
end
$$;

-- Spends the caller's diamonds: 'convert' (into gold, which the phone adds) or
-- 'item' (a premium cosmetic; p_ref names it, e.g. "world:neon").
-- Returns {"diamonds": new balance}; raises when there are not enough.
-- Owned items and gold still live in the phone's save, so this guards the
-- diamonds themselves, not what was bought with them.
create or replace function public.spend_diamonds(
  p_amount integer,
  p_reason text,
  p_ref text default ''
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;
  if p_amount is null or p_amount < 1 or p_amount > 10000 then
    raise exception 'invalid amount';
  end if;
  if p_reason is null or p_reason not in ('convert', 'item') then
    raise exception 'invalid reason';
  end if;
  return jsonb_build_object(
    'diamonds', spikey_change_diamonds(v_uid, -p_amount, p_reason, p_ref)
  );
end
$$;

revoke all on function public.spikey_daily_prize(integer) from public, anon, authenticated;
revoke all on function public.spikey_change_diamonds(uuid, integer, text, text)
  from public, anon, authenticated;
revoke all on function public.spikey_settle_days() from public, anon, authenticated;
revoke all on function public.spikey_award_bonuses(uuid) from public, anon, authenticated;
revoke all on function public.get_wallet() from public, anon;
revoke all on function public.claim_prizes() from public, anon;
revoke all on function public.spend_diamonds(integer, text, text) from public, anon;
grant execute on function public.get_wallet() to authenticated;
grant execute on function public.claim_prizes() to authenticated;
grant execute on function public.spend_diamonds(integer, text, text) to authenticated;
