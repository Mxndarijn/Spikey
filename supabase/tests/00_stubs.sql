-- What a Supabase project has that plain Postgres lacks, as small stand-ins.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
create schema auth;
create table auth.users (id uuid primary key);
-- Supabase reads the signed-in player from the request's JWT.
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant usage on schema auth to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
-- pg_net: the calls to GitHub and to the alert sender. Here they are only
-- written down, so tests can see who would have been called.
create schema net;
create table net.calls (id bigint generated always as identity, url text, headers jsonb);
create function net.http_post(
  url text, body jsonb default '{}'::jsonb, params jsonb default '{}'::jsonb,
  headers jsonb default '{}'::jsonb, timeout_milliseconds integer default 5000
) returns bigint language sql as $$
  insert into net.calls (url, headers) values (url, headers) returning id
$$;
grant usage on schema public to anon, authenticated;
