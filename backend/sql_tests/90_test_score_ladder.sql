-- The score ladder (20261114120000_score_ladder.sql): 3 diamonds for each 50
-- from 150 to 1000, once, above the player's mark. Any wrong result raises.
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
create or replace function t_lrun(n integer, p_score integer, p_status text)
returns void language sql as $$
  insert into runs (player_id, score, day, played_at, gameplay_version, seed, status)
  values (t_uid(n), p_score, spikey_today(), now(), 14, 1, p_status)
$$;
-- The ladder steps a player won, lowest first.
create or replace function t_steps(n integer) returns jsonb language sql as $$
  select coalesce(jsonb_agg(b.ref::integer order by b.ref::integer), '[]'::jsonb)
  from bonus_prizes b
  where b.player_id = t_uid(n) and b.kind = 'milestone' and b.ref::integer >= 150
$$;
create or replace function t_step_diamonds(n integer) returns integer language sql as $$
  select coalesce(sum(b.diamonds), 0)::integer
  from bonus_prizes b
  where b.player_id = t_uid(n) and b.kind = 'milestone' and b.ref::integer >= 150
$$;

insert into auth.users (id) select t_uid(n) from generate_series(951, 957) n;
insert into players (id, name) select t_uid(n), 'Ladder' || n from generate_series(951, 957) n;

do $$
declare
  s jsonb;
begin
  -- 952 and 956 played before the ladder came: their best is their mark.
  perform t_lrun(952, 420, 'ok');
  insert into run_carry (player_id, best, coins) values (t_uid(956), 300, 0);
  perform t_lrun(956, 120, 'ok');
  perform spikey_mark_ladder();
  perform t_eq((select l.best from ladder_marks l where l.player_id = t_uid(952)), 420,
    'an old best is the mark');
  perform t_eq((select l.best from ladder_marks l where l.player_id = t_uid(956)), 300,
    'a best carried over a reset is the mark');

  -- 952: no back-pay. 150 to 400 never pay; 450 does.
  perform t_as(952);
  s := get_earn_status();
  perform t_eq((s->>'ladder_mark')::integer, 420, 'get_earn_status gives the mark');
  perform t_eq(s->'milestones', '[25, 50, 75, 100]'::jsonb, 'no step at or below the mark');
  perform t_lrun(952, 460, 'ok');
  s := get_earn_status();
  perform t_eq(s->'milestones', '[25, 50, 75, 100, 450]'::jsonb, 'a new step above the mark');
  perform t_eq(t_step_diamonds(952), 3, 'a step pays 3');
  -- Marking again keeps the first mark.
  perform spikey_mark_ladder();
  perform t_eq((select l.best from ladder_marks l where l.player_id = t_uid(952)), 420,
    'the mark never moves');

  -- 956: the carried best is the mark too.
  perform t_lrun(956, 340, 'ok');
  perform t_as(956);
  s := get_earn_status();
  perform t_eq(t_steps(956), '[]'::jsonb, 'nothing up to a carried mark of 300');
  perform t_lrun(956, 350, 'ok');
  s := get_earn_status();
  perform t_eq(t_steps(956), '[350]'::jsonb, 'the step just past the carried mark');

  -- 951: a new player (no mark): one run of 212 pays 150 and 200.
  perform t_lrun(951, 212, 'ok');
  perform t_as(951);
  s := get_earn_status();
  perform t_eq((s->>'ladder_mark')::integer, 0, 'a new player starts at 0');
  perform t_eq(s->'milestones', '[25, 50, 75, 100, 150, 200]'::jsonb,
    'one run passing two steps pays both');
  perform t_eq(t_step_diamonds(951), 6, 'two steps pay 6');
  -- Again and again: one row each.
  s := get_earn_status();
  perform t_eq(t_step_diamonds(951), 6, 'asking again pays nothing more');
  -- A lower run later changes nothing; a higher one adds the steps between.
  perform t_lrun(951, 180, 'ok');
  perform t_lrun(951, 263, 'ok');
  s := get_earn_status();
  perform t_eq(t_steps(951), '[150, 200, 250]'::jsonb, 'a better best adds the next step');

  -- 953: the ladder ends at 1000.
  perform t_lrun(953, 1500, 'ok');
  perform t_as(953);
  s := get_earn_status();
  perform t_eq(jsonb_array_length(t_steps(953)), 18, 'eighteen steps, 150 to 1000');
  perform t_eq(t_step_diamonds(953), 54, 'all steps pay 54');
  perform t_eq((t_steps(953)->>17)::integer, 1000, 'the top step is 1000');

  -- 954: unchecked scores don't count; 149 is short of the first step.
  perform t_lrun(954, 300, 'rejected');
  perform t_lrun(954, 280, 'pending');
  perform t_lrun(954, 149, 'ok');
  perform t_as(954);
  s := get_earn_status();
  perform t_eq(t_steps(954), '[]'::jsonb, 'only checked runs reach a step');
  perform t_lrun(954, 150, 'ok');
  s := get_earn_status();
  perform t_eq(t_steps(954), '[150]'::jsonb, 'exactly 150 reaches it');

  -- 955: steps are claimed with the other prizes and stay won.
  perform t_lrun(955, 155, 'ok');
  perform t_as(955);
  s := get_wallet();
  s := claim_prizes();
  perform t_eq((select count(*)::integer from bonus_prizes b
    where b.player_id = t_uid(955) and b.claimed_at is null), 0, 'claim takes the steps too');
  perform t_eq((s->>'diamonds')::integer, 10, 'four milestones (7) and one step (3)');
  s := get_earn_status();
  perform t_eq(t_steps(955), '[150]'::jsonb, 'a claimed step still counts as won');
end $$;

select 'ALL DATABASE TESTS PASSED' as result;
