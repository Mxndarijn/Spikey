-- Wake the checker when a run arrives, instead of waiting for its 10-minute
-- schedule (which GitHub often starts late). Every new run asks GitHub to start
-- .github/workflows/verify-runs.yml right away; the schedule stays as a safety
-- net for anything this misses.
--
-- It needs a GitHub token that may start workflows (docs/LEADERBOARD_SETUP.md,
-- "Verification"). verify-runs.yml stores it here with worker_set_wake. Without
-- a token nothing happens and the schedule does all the work, as before.

-- Sends the request in the background, after the run is saved.
create extension if not exists pg_net;

-- Settings only the checker's side may read (locked: row level security on, no
-- policies, like the other tables).
create table if not exists public.worker_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

alter table public.worker_settings enable row level security;
revoke all on table public.worker_settings from public, anon, authenticated;

-- For the checker only: remember the token and the repository ("owner/name")
-- whose verify-runs.yml to start. An empty token turns the wake-up off.
create or replace function public.worker_set_wake(p_token text, p_repo text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(p_token, '') = '' or coalesce(p_repo, '') !~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' then
    delete from worker_settings where key in ('wake_token', 'wake_repo');
    return;
  end if;
  insert into worker_settings (key, value)
  values ('wake_token', p_token), ('wake_repo', p_repo)
  on conflict (key) do update
    set value = excluded.value, updated_at = now()
    where worker_settings.value is distinct from excluded.value;
end
$$;

-- Asks GitHub to start the checker. Never fails: a run must be saved even when
-- the wake-up can't be sent (the schedule picks it up later).
create or replace function public.spikey_wake_checker() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_token text;
  v_repo text;
begin
  select value into v_token from worker_settings where key = 'wake_token';
  select value into v_repo from worker_settings where key = 'wake_repo';
  if v_token is null or v_repo is null then
    return null;
  end if;
  begin
    perform net.http_post(
      url := 'https://api.github.com/repos/' || v_repo
        || '/actions/workflows/verify-runs.yml/dispatches',
      body := jsonb_build_object('ref', 'main'),
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || v_token,
        'Accept', 'application/vnd.github+json',
        'Content-Type', 'application/json',
        'User-Agent', 'flapjaw-leaderboard',
        'X-GitHub-Api-Version', '2022-11-28'
      )
    );
  exception when others then
    null;
  end;
  return null;
end
$$;

drop trigger if exists runs_wake_checker on public.runs;
create trigger runs_wake_checker
  after insert on public.runs
  for each statement execute function public.spikey_wake_checker();

revoke all on function public.worker_set_wake(text, text) from public, anon, authenticated;
revoke all on function public.spikey_wake_checker() from public, anon, authenticated;
