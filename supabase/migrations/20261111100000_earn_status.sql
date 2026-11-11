-- What the Earn diamonds screen shows about the caller: their best checked
-- score, which best-score milestones they won (claimed or not) and their
-- current streak of days with a checked run. Read only apart from the same
-- prize bookkeeping get_wallet does (settling days, writing earned bonuses).
-- The daily place comes from the Daily board itself.
--
-- {"best": 87, "milestones": [25, 50, 75],
--  "streak": 4, "played_today": true, "streak_won": 0}
--
-- streak: days in a row ending today or yesterday (a row that ended before
-- yesterday is broken: 0). streak_won: streak diamonds won in that row.

create or replace function public.get_earn_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_today date := spikey_today();
  v_first date;
  v_last date;
  v_len integer := 0;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;
  perform spikey_settle_days();
  perform spikey_award_bonuses(v_uid);
  -- The latest unbroken row of days, the same way spikey_award_bonuses finds it.
  with days as (
    select distinct r.day
    from runs r
    where r.player_id = v_uid and r.status = 'ok' and r.day > v_today - 400
  ), grouped as (
    select d.day, d.day - (row_number() over (order by d.day))::integer as grp
    from days d
  )
  select min(g.day), max(g.day), count(*)::integer into v_first, v_last, v_len
  from grouped g
  group by g.grp
  order by max(g.day) desc
  limit 1;
  if v_last is null or v_last < v_today - 1 then
    v_len := 0;
  end if;
  return jsonb_build_object(
    'best', coalesce((
      select max(r.score) from runs r where r.player_id = v_uid and r.status = 'ok'
    ), 0),
    'milestones', coalesce((
      select jsonb_agg(b.ref::integer order by b.ref::integer)
      from bonus_prizes b
      where b.player_id = v_uid and b.kind = 'milestone'
    ), '[]'::jsonb),
    'streak', coalesce(v_len, 0),
    'played_today', coalesce(v_last = v_today, false),
    'streak_won', case when coalesce(v_len, 0) = 0 then 0 else (
      select count(*)::integer from bonus_prizes b
      where b.player_id = v_uid and b.kind = 'streak' and b.ref::date >= v_first
    ) end
  );
end
$$;

revoke all on function public.get_earn_status() from public, anon;
grant execute on function public.get_earn_status() to authenticated;
