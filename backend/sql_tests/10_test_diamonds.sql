-- Runs the diamonds functions against real tables. Any wrong result raises.
\set ON_ERROR_STOP on

create or replace function t_uid(n integer) returns uuid language sql immutable as $$
  select ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid
$$;
create or replace function t_as(n integer) returns void language sql as $$
  select set_config('request.jwt.claim.sub', t_uid(n)::text, false)
$$;
create or replace function t_eq(got anyelement, want anyelement, what text) returns void
language plpgsql as $$
begin
  if got is distinct from want then
    raise exception 'FAIL %: expected %, got %', what, want, got;
  end if;
  raise notice 'ok   %', what;
end $$;
create or replace function t_run(n integer, p_score integer, p_day date, p_status text,
                                 p_at timestamptz default null) returns void
language sql as $$
  insert into runs (player_id, score, day, played_at, gameplay_version, seed, status)
  values (t_uid(n), p_score, p_day, coalesce(p_at, p_day::timestamp + interval '12 hours'),
          14, 1, p_status)
$$;

-- 13 players with a row, player 99 signed in but without one.
insert into auth.users (id) select t_uid(n) from generate_series(1, 13) n;
insert into auth.users (id) values (t_uid(99));
insert into players (id, name) select t_uid(n), 'Player' || n from generate_series(1, 13) n;

do $$
declare
  y date := spikey_today() - 1;
  w jsonb;
  c jsonb;
  s jsonb;
  failed boolean;
begin
  -- Yesterday's board. Scores: p1 100, p2 95 (noon), p3 95 (one hour later),
  -- p4..p11 80 down to 73, p12 a rejected 999, p13 nothing.
  perform t_run(1, 100, y, 'ok');
  perform t_run(1, 40, y, 'ok');
  perform t_run(2, 95, y, 'ok', y::timestamp + interval '12 hours');
  perform t_run(3, 95, y, 'ok', y::timestamp + interval '13 hours');
  for n in 4..11 loop
    perform t_run(n, 84 - n, y, 'ok');
  end loop;
  perform t_run(12, 999, y, 'rejected');
  -- One of yesterday's runs still waits for the checker.
  perform t_run(13, 5, y, 'pending');
  -- Three days back: one checked run and one that got stuck waiting.
  perform t_run(8, 60, y - 2, 'ok');
  perform t_run(9, 70, y - 2, 'pending');

  perform t_as(1);
  w := get_wallet();
  perform t_eq((w->>'diamonds')::integer, 0, 'new wallet is empty');
  perform t_eq(jsonb_array_length(w->'prizes'), 0, 'no payout while a run of that day is pending');
  perform t_eq((select count(*)::integer from settled_days where day = y), 0,
               'yesterday is not settled yet');
  perform t_eq((select rank from daily_prizes where day = y - 2 and player_id = t_uid(8)), 1,
               'an older day no longer waits for a stuck run');
  perform t_eq((select count(*)::integer from daily_prizes where day = y - 2), 1,
               'and the stuck run wins nothing');
  perform t_eq(jsonb_array_length(w->'bonuses'), 4, 'p1 (best 100) earned four milestones');

  update runs set status = 'ok' where player_id = t_uid(13) and status = 'pending';
  w := get_wallet();
  perform t_eq(jsonb_array_length(w->'prizes'), 1, 'p1 has one daily prize');
  perform t_eq((w->'prizes'->0->>'rank')::integer, 1, 'p1 is first');
  perform t_eq((w->'prizes'->0->>'diamonds')::integer, 3, 'first place pays 3');
  perform t_eq((w->'prizes'->0->>'score')::integer, 100, 'with the best run');
  perform t_eq((select count(*)::integer from daily_prizes where day = y), 10, 'ten places are paid');
  perform t_eq((select sum(diamonds)::integer from daily_prizes where day = y), 14, '14 diamonds a day');
  perform t_eq((select rank from daily_prizes where day = y and player_id = t_uid(2)), 2,
               'on a tie the earlier run is 2nd');
  perform t_eq((select rank from daily_prizes where day = y and player_id = t_uid(3)), 3, 'the later one 3rd');
  perform t_eq((select diamonds from daily_prizes where day = y and player_id = t_uid(3)), 2, '3rd pays 2');
  perform t_eq((select diamonds from daily_prizes where day = y and player_id = t_uid(4)), 1, '4th pays 1');
  perform t_eq((select rank from daily_prizes where day = y and player_id = t_uid(10)), 10, 'p10 is 10th');
  perform t_eq((select count(*)::integer from daily_prizes where day = y and player_id = t_uid(11)), 0,
               '11th wins nothing');
  perform t_eq((select count(*)::integer from daily_prizes where day = y and player_id = t_uid(12)), 0,
               'a rejected run wins nothing');

  w := get_wallet();
  perform t_eq((select count(*)::integer from daily_prizes where day = y), 10, 'asking again pays nothing twice');
  perform t_eq((select count(*)::integer from bonus_prizes where player_id = t_uid(1)), 4,
               'milestones are written once');

  -- Claim: 3 (daily) + 1 + 1 + 2 + 3 (milestones 25, 50, 75, 100).
  c := claim_prizes();
  perform t_eq((c->>'claimed')::integer, 10, 'claim adds daily prize and milestones');
  perform t_eq((c->>'diamonds')::integer, 10, 'the balance after claiming');
  c := claim_prizes();
  perform t_eq((c->>'claimed')::integer, 0, 'claiming twice adds nothing');
  perform t_eq((c->>'diamonds')::integer, 10, 'and keeps the balance');
  perform t_eq((select count(*)::integer from diamond_ledger where player_id = t_uid(1)), 5,
               'five ledger lines');
  perform t_eq((select sum(amount)::integer from diamond_ledger where player_id = t_uid(1)), 10,
               'the ledger adds up to the balance');
  w := get_wallet();
  perform t_eq(jsonb_array_length(w->'prizes') + jsonb_array_length(w->'bonuses'), 0,
               'nothing left to claim');

  -- Spending.
  s := spend_diamonds(4, 'convert');
  perform t_eq((s->>'diamonds')::integer, 6, 'spending 4 leaves 6');
  s := spend_diamonds(6, 'item', 'world:neon');
  perform t_eq((s->>'diamonds')::integer, 0, 'spending down to zero works');
  perform t_eq((select ref from diamond_ledger where reason = 'item'), 'world:neon',
               'the ledger says what was bought');
  failed := false;
  begin
    perform spend_diamonds(1, 'item', 'x');
  exception when others then
    failed := sqlerrm = 'not enough diamonds';
  end;
  perform t_eq(failed, true, 'overspending is refused');
  perform t_eq((select diamonds from wallets where player_id = t_uid(1)), 0,
               'a refused spend changes nothing');
  failed := false;
  begin
    perform spend_diamonds(1, 'pack', '');
  exception when others then
    failed := sqlerrm = 'invalid reason';
  end;
  perform t_eq(failed, true, 'the game cannot grant itself a pack');
  failed := false;
  begin
    perform spend_diamonds(-5, 'convert', '');
  exception when others then
    failed := sqlerrm = 'invalid amount';
  end;
  perform t_eq(failed, true, 'a negative spend (a gift) is refused');

  -- Someone signed in who never played.
  perform t_as(99);
  w := get_wallet();
  perform t_eq((w->>'diamonds')::integer, 0, 'no player row: an empty wallet');
  failed := false;
  begin
    perform spend_diamonds(1, 'convert', '');
  exception when others then
    failed := sqlerrm = 'not enough diamonds';
  end;
  perform t_eq(failed, true, 'no player row: nothing to spend');

  -- Nobody signed in.
  perform set_config('request.jwt.claim.sub', '', false);
  failed := false;
  begin
    perform get_wallet();
  exception when others then
    failed := sqlerrm = 'not signed in';
  end;
  perform t_eq(failed, true, 'signed out: no wallet');
end $$;

-- Streaks: p5 plays 15 days in a row ending today, p6 six days, p7 seven days
-- with a hole in them.
do $$
declare
  t date := spikey_today();
  w jsonb;
begin
  for d in 0..14 loop
    perform t_run(5, 30, t - d, 'ok');
  end loop;
  for d in 0..5 loop
    perform t_run(6, 10, t - d, 'ok');
  end loop;
  for d in 0..7 loop
    if d <> 3 then
      perform t_run(7, 10, t - d, 'ok');
    end if;
  end loop;
  perform t_as(5);
  w := get_wallet();
  perform t_eq((select count(*)::integer from bonus_prizes
                where player_id = t_uid(5) and kind = 'streak'), 2, '15 days in a row: two streaks');
  perform t_eq((select min(ref) from bonus_prizes where player_id = t_uid(5) and kind = 'streak'),
               (t - 8)::text, 'the first streak prize is for the 7th day');
  perform t_eq((select count(*)::integer from bonus_prizes
                where player_id = t_uid(5) and kind = 'milestone'), 3, 'best 79: milestones 25, 50, 75');
  w := get_wallet();
  perform t_eq((select count(*)::integer from bonus_prizes
                where player_id = t_uid(5) and kind = 'streak'), 2, 'streaks are written once');
  perform t_as(6);
  w := get_wallet();
  perform t_eq((select count(*)::integer from bonus_prizes
                where player_id = t_uid(6) and kind = 'streak'), 0, 'six days: no streak');
  perform t_as(7);
  w := get_wallet();
  perform t_eq((select count(*)::integer from bonus_prizes
                where player_id = t_uid(7) and kind = 'streak'), 0, 'a missed day breaks the streak');
end $$;

-- Late runs and old days.
do $$
declare
  y date := spikey_today() - 1;
  w jsonb;
begin
  perform t_run(11, 500, y, 'ok');
  perform t_as(11);
  w := get_wallet();
  perform t_eq(jsonb_array_length(w->'prizes'), 0, 'a run arriving after the payout wins nothing');
end $$;

-- What the game's own role may and may not do.
do $$
declare
  denied boolean;
begin
  perform t_as(1);
  set local role authenticated;
  perform get_wallet();
  raise notice 'ok   a signed-in player may read their wallet';
  denied := false;
  begin
    perform spikey_change_diamonds(t_uid(1), 1000, 'pack', 'free');
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then raise exception 'FAIL the game can add diamonds itself'; end if;
  raise notice 'ok   the game cannot add diamonds itself';
  denied := false;
  begin
    perform spikey_award_bonuses(t_uid(1));
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then raise exception 'FAIL the game can call spikey_award_bonuses'; end if;
  raise notice 'ok   the game cannot award bonuses itself';
  denied := false;
  begin
    update wallets set diamonds = 999;
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then raise exception 'FAIL the game can write wallets'; end if;
  raise notice 'ok   the game cannot write the wallets table';
  reset role;
  set local role anon;
  denied := false;
  begin
    perform get_wallet();
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then raise exception 'FAIL anon can read a wallet'; end if;
  raise notice 'ok   a visitor without a session gets nothing';
  reset role;
end $$;

select 'ALL DATABASE TESTS PASSED' as result;
