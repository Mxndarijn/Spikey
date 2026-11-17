-- The board function after every migration: a row carries both the name plate
-- (cosmetics) and the revive mark (revives). Two migrations redefine get_board;
-- this catches one undoing the other. Any wrong result raises.
\set ON_ERROR_STOP on

insert into auth.users (id) values ('00000000-0000-0000-0000-00000000b0a1');
insert into players (id, name) values ('00000000-0000-0000-0000-00000000b0a1', 'Boardy');
insert into runs (player_id, score, day, played_at, gameplay_version, seed, status, loadout, revives)
values ('00000000-0000-0000-0000-00000000b0a1', 42, spikey_today(), now(), 15, 1, 'ok',
        '{"plate": "royal"}'::jsonb, '[120]'::jsonb);

do $$
declare
  b jsonb;
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000b0a1', false);
  b := get_board('daily');
  if b->'entries'->0->>'plate' is distinct from 'royal' then
    raise exception 'FAIL the board row lost its name plate: %', b->'entries'->0;
  end if;
  raise notice 'ok   a board row carries its name plate';
  if (b->'entries'->0->>'revived')::boolean is distinct from true then
    raise exception 'FAIL the board row lost its revive mark: %', b->'entries'->0;
  end if;
  raise notice 'ok   a board row carries its revive mark';
  if (b->'me'->>'revived')::boolean is distinct from true then
    raise exception 'FAIL the player''s own entry lost its revive mark: %', b->'me';
  end if;
  raise notice 'ok   the player''s own entry carries its revive mark';
end $$;

delete from runs where player_id = '00000000-0000-0000-0000-00000000b0a1';
select 'ALL DATABASE TESTS PASSED' as result;
