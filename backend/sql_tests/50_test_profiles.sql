-- Runs sync_profile against a real table. Any wrong result raises.
\set ON_ERROR_STOP on

create or replace function t_uid(n integer) returns uuid language sql immutable as $$
  select ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid
$$;
create or replace function t_as(n integer) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(t_uid(n)::text, ''), false)
$$;
create or replace function t_eq(got anyelement, want anyelement, what text) returns void
language plpgsql as $$
begin
  if got is distinct from want then
    raise exception 'FAIL %: expected %, got %', what, want, got;
  end if;
  raise notice 'ok   %', what;
end $$;

insert into auth.users (id) values (t_uid(501)), (t_uid(502));

do $$
declare
  r jsonb;
  failed boolean;
begin
  perform t_as(501);
  r := sync_profile('{"coins": 10}', 0);
  perform t_eq(r - 'paid', '{"status": "saved", "revision": 1}'::jsonb, 'the first save is kept');
  r := sync_profile('{"coins": 20}', 1);
  perform t_eq(r - 'paid', '{"status": "saved", "revision": 2}'::jsonb, 'a save on the newest one');
  r := sync_profile('{"coins": 5}', 1);
  perform t_eq(r ->> 'status', 'conflict', 'a save on an old revision is refused');
  perform t_eq((r ->> 'revision')::int, 2, 'and gets the newest revision');
  perform t_eq(r -> 'data', '{"coins": 20}'::jsonb, 'and the newest save');
  r := sync_profile('{"coins": 0}', 0);
  perform t_eq(r ->> 'status', 'conflict', 'a new phone gets the save back first');
  perform t_eq(
    (select data from profiles where player_id = t_uid(501)), '{"coins": 20}'::jsonb,
    'nothing overwritten'
  );

  perform t_as(502);
  r := sync_profile('{"coins": 1}', 7);
  perform t_eq(r ->> 'status', 'saved', 'no row yet: any base is kept');
  perform t_eq(
    (select data from profiles where player_id = t_uid(501)), '{"coins": 20}'::jsonb,
    'each player has their own row'
  );

  failed := false;
  begin
    perform sync_profile('[1, 2]', 1);
  exception when others then
    failed := true;
  end;
  perform t_eq(failed, true, 'only an object is a profile');

  failed := false;
  begin
    perform sync_profile(jsonb_build_object('x', repeat('a', 70000)), 1);
  exception when others then
    failed := true;
  end;
  perform t_eq(failed, true, 'a huge profile is refused');

  perform set_config('request.jwt.claim.sub', '', false);
  failed := false;
  begin
    perform sync_profile('{}', 0);
  exception when others then
    failed := true;
  end;
  perform t_eq(failed, true, 'signed in only');

  perform t_eq(
    has_function_privilege('anon', 'public.sync_profile(jsonb, bigint)', 'execute'), false,
    'anon may not call it'
  );
end $$;

select 'ALL DATABASE TESTS PASSED';
