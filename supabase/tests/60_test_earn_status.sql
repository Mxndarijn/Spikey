-- get_earn_status: best checked score, milestones won and the current streak.
-- Any wrong result raises.
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
create or replace function t_run(n integer, p_score integer, p_day date, p_status text)
returns void language sql as $$
  insert into runs (player_id, score, day, played_at, gameplay_version, seed, status)
  values (t_uid(n), p_score, p_day, p_day::timestamp + interval '12 hours', 14, 1, p_status)
$$;

insert into auth.users (id) select t_uid(n) from generate_series(701, 705) n;
insert into players (id, name) select t_uid(n), 'Earn' || n from generate_series(701, 705) n;

do $$
declare
  t date := spikey_today();
  s jsonb;
begin
  -- 701: no runs at all.
  perform t_as(701);
  s := get_earn_status();
  perform t_eq((s->>'best')::integer, 0, 'a new player has no best');
  perform t_eq(s->'milestones', '[]'::jsonb, 'and no milestones');
  perform t_eq((s->>'streak')::integer, 0, 'and no streak');
  perform t_eq((s->>'played_today')::boolean, false, 'and no run today');

  -- 702: best 80 checked (a rejected 120 counts for nothing), 9 days in a
  -- row ending today.
  for d in 0..8 loop
    perform t_run(702, 20, t - d, 'ok');
  end loop;
  perform t_run(702, 80, t - 3, 'ok');
  perform t_run(702, 120, t, 'rejected');
  perform t_as(702);
  s := get_earn_status();
  perform t_eq((s->>'best')::integer, 80, 'only checked runs make the best');
  perform t_eq(s->'milestones', '[25, 50, 75]'::jsonb, 'milestones up to the best');
  perform t_eq((s->>'streak')::integer, 9, 'nine days in a row');
  perform t_eq((s->>'played_today')::boolean, true, 'played today');
  perform t_eq((s->>'streak_won')::integer, 1, 'one streak diamond in this row');
  -- Claiming keeps them on the list.
  perform claim_prizes();
  s := get_earn_status();
  perform t_eq(s->'milestones', '[25, 50, 75]'::jsonb, 'claimed milestones still count as won');

  -- 703: played up to yesterday: the row still counts, today not played.
  for d in 1..3 loop
    perform t_run(703, 30, t - d, 'ok');
  end loop;
  perform t_as(703);
  s := get_earn_status();
  perform t_eq((s->>'streak')::integer, 3, 'a row up to yesterday still counts');
  perform t_eq((s->>'played_today')::boolean, false, 'today is still open');

  -- 704: the last run was two days ago: the streak is broken.
  for d in 2..9 loop
    perform t_run(704, 30, t - d, 'ok');
  end loop;
  perform t_as(704);
  s := get_earn_status();
  perform t_eq((s->>'streak')::integer, 0, 'a missed day breaks the streak');
  perform t_eq((s->>'streak_won')::integer, 0, 'and a broken row shows no streak diamonds');

  -- 705: only a pending run today: nothing yet.
  perform t_run(705, 60, t, 'pending');
  perform t_as(705);
  s := get_earn_status();
  perform t_eq((s->>'best')::integer, 0, 'a run waiting for the checker does not count yet');
  perform t_eq((s->>'streak')::integer, 0, 'nor for the streak');

  perform t_eq(
    has_function_privilege('anon', 'public.get_earn_status()', 'execute'),
    false, 'signed-out callers cannot use it'
  );
end $$;

select 'ALL DATABASE TESTS PASSED' as result;
