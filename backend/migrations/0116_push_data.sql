-- A tapped battle push opens its battle: the sender gets the battle id with
-- each battle alert (from its ref, "turn:12:3", "nudge:12:2026-11-17", ...).
-- As in 0110_battles.sql otherwise.
create or replace function public.worker_pending_alerts(p_limit integer default 100) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x.alert order by x.at), '[]'::jsonb)
  from (
    select a.created_at as at, jsonb_build_object(
      'id', a.id, 'token', d.token, 'platform', d.platform, 'title', a.title, 'body', a.body,
      'line', a.line
    ) as alert
    from (
      select * from spot_alerts
      where status = 'queued' and created_at > now() - interval '30 minutes'
      order by id
      limit greatest(1, least(coalesce(p_limit, 100), 500))
    ) a
    join push_devices d on d.player_id = a.player_id and d.enabled
    union all
    select a.created_at, jsonb_build_object(
      'id', -a.id, 'token', d.token, 'platform', d.platform, 'title', a.title, 'body', a.body,
      'line', 'battle', 'battle', split_part(a.ref, ':', 2)
    )
    from (
      select * from battle_alerts
      where status = 'queued' and created_at > now() - interval '30 minutes'
      order by id
      limit greatest(1, least(coalesce(p_limit, 100), 500))
    ) a
    join push_devices d on d.player_id = a.player_id and d.enabled
  ) x
$$;
revoke all on function public.worker_pending_alerts(integer) from public, anon, authenticated;
