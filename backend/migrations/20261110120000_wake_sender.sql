-- Wake the sender when a Board alert was queued, so a notification goes out
-- seconds after the checker passed the run that caused it.
--
-- The sender is the Edge Function supabase/functions/send-alerts. It needs to
-- know where it lives and a shared secret; .github/workflows/supabase-functions.yml
-- stores both here with worker_set_push when it deploys the function. Without
-- them nothing is sent: alerts stay in the outbox (and expire after 30 minutes).

-- For the deploy workflow only: where the sender is and the secret it expects.
-- An empty value turns sending off.
create or replace function public.worker_set_push(p_url text, p_secret text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(p_secret, '') = '' or coalesce(p_url, '') !~ '^https://[A-Za-z0-9./_-]+$' then
    delete from worker_settings where key in ('push_url', 'push_secret');
    return;
  end if;
  insert into worker_settings (key, value)
  values ('push_url', p_url), ('push_secret', p_secret)
  on conflict (key) do update
    set value = excluded.value, updated_at = now()
    where worker_settings.value is distinct from excluded.value;
end
$$;

-- Same trigger function as before, now also calling the sender when the check
-- queued something. Still never fails: the checker's work always stands.
create or replace function public.spikey_runs_checked() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_today date := spikey_today();
  v_queued integer;
  v_url text;
  v_secret text;
begin
  if exists (select 1 from changed c where c.status = 'ok' and c.day = v_today) then
    begin
      v_queued := spikey_check_spots(v_today);
      if v_queued > 0 then
        select value into v_url from worker_settings where key = 'push_url';
        select value into v_secret from worker_settings where key = 'push_secret';
        if v_url is not null and v_secret is not null then
          perform net.http_post(
            url := v_url,
            body := '{}'::jsonb,
            headers := jsonb_build_object(
              'Authorization', 'Bearer ' || v_secret,
              'Content-Type', 'application/json'
            )
          );
        end if;
      end if;
    exception when others then
      null;
    end;
  end if;
  return null;
end
$$;

revoke all on function public.worker_set_push(text, text) from public, anon, authenticated;
revoke all on function public.spikey_runs_checked() from public, anon, authenticated;
