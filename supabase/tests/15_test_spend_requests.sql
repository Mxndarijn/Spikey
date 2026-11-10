-- A spend asked for twice with one request id is charged once.
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

insert into auth.users (id) values (t_uid(301));
insert into players (id, name) values (t_uid(301), 'Spender');
insert into wallets (player_id, diamonds) values (t_uid(301), 50);

do $$
declare
  s jsonb;
  req uuid := '11111111-2222-4333-8444-555555555555';
begin
  perform t_as(301);
  s := spend_diamonds(20, 'item', 'world:neon', req);
  perform t_eq((s->>'diamonds')::integer, 30, 'the first call spends');
  s := spend_diamonds(20, 'item', 'world:neon', req);
  perform t_eq((s->>'diamonds')::integer, 30, 'a repeat answers the same balance');
  perform t_eq((s->>'repeat')::boolean, true, 'and says it is a repeat');
  perform t_eq((select diamonds from wallets where player_id = t_uid(301)), 30,
               'charged once');
  perform t_eq((select count(*)::integer from diamond_ledger where player_id = t_uid(301)), 1,
               'one ledger line');
  s := spend_diamonds(5, 'convert', '', '99999999-2222-4333-8444-555555555555');
  perform t_eq((s->>'diamonds')::integer, 25, 'a new id is a new spend');
  s := spend_diamonds(5, 'convert');
  perform t_eq((s->>'diamonds')::integer, 20, 'older builds without an id still spend');
end $$;

select 'ALL DATABASE TESTS PASSED' as result;
