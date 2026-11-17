-- Name plates: each board row says which plate the player had in use on their
-- best run (the "plate" key of the run's loadout, a cosmetic). The client
-- draws it behind the row; an id it doesn't know, or none, is the plain row.
-- Nothing else about the boards changes: this is the board function of the
-- revives migration (each row says whether its run used a revive) with the
-- plate added. It runs after that migration, so neither undoes the other.
create or replace function public.get_board(p_board text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_today date := spikey_today();
  v_result jsonb;
begin
  if p_board not in ('daily', 'all_time') then
    raise exception 'unknown board %', p_board;
  end if;
  with best as (
    select distinct on (r.player_id) r.player_id, r.score, r.id as run_id,
           r.status = 'ok' as verified,
           jsonb_array_length(r.revives) > 0 as revived,
           coalesce(left(r.loadout->>'plate', 40), '') as plate
    from runs r
    where (p_board = 'all_time' or r.day = v_today)
      and (r.status = 'ok' or (r.status = 'pending' and r.player_id = auth.uid()))
    order by r.player_id, r.score desc, r.played_at asc
  ), ranked as (
    select b.player_id, b.score, b.run_id, b.verified, b.revived, b.plate, p.name, p.flyer,
           rank() over (order by b.score desc) as rank
    from best b
    join players p on p.id = b.player_id
  )
  select jsonb_build_object(
    'entries', coalesce((
      select jsonb_agg(jsonb_build_object(
        'rank', t.rank, 'name', t.name, 'flyer', t.flyer, 'score', t.score,
        'is_me', t.player_id = auth.uid(), 'run', t.run_id, 'verified', t.verified,
        'revived', t.revived, 'plate', t.plate
      ) order by t.rank, t.name)
      from (select * from ranked order by rank, name limit 100) t
    ), '[]'::jsonb),
    'me', (
      select jsonb_build_object(
        'rank', rank, 'score', score, 'run', run_id, 'verified', verified, 'revived', revived
      )
      from ranked where player_id = auth.uid()
    ),
    'players', (select count(*) from ranked),
    'resets_in_s', case
      when p_board = 'daily' then extract(epoch from spikey_next_midnight() - now())::integer
      else -1
    end
  ) into v_result;
  return v_result;
end
$$;
