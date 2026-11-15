-- What the Supabase migrations expect from the platform, on plain Postgres.
-- The same stand-ins the database tests use (supabase/tests/00_stubs.sql):
-- the roles the grants name, auth.users and auth.uid(), and net.http_post.
-- The server signs players in itself (backend.sessions) and sets
-- request.jwt.claim.sub for each call, so the SQL functions read the player
-- exactly as they did on Supabase.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin;
  end if;
end $$;

create schema if not exists auth;
create table if not exists auth.users (
  id uuid primary key,
  created_at timestamptz not null default now()
);
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant usage on schema auth to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;

-- pg_net: on Supabase the database called GitHub (the checker) and the alert
-- sender over HTTP. Here the server does both itself (it checks runs as they
-- arrive and sends queued alerts), so the calls are only written down.
create schema if not exists net;
create table if not exists net.calls (
  id bigint generated always as identity,
  url text,
  headers jsonb,
  at timestamptz not null default now()
);
create or replace function net.http_post(
  url text, body jsonb default '{}'::jsonb, params jsonb default '{}'::jsonb,
  headers jsonb default '{}'::jsonb, timeout_milliseconds integer default 5000
) returns bigint language sql as $$
  insert into net.calls (url, headers) values (url, headers) returning id
$$;
grant usage on schema public to anon, authenticated;
