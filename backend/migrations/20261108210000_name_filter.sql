-- Bad-word filter for leaderboard names.
-- The words live in public.banned_words. Add more in the dashboard (Table Editor ->
-- banned_words -> Insert row): lower case letters only. whole_only = true for short
-- words that also hide inside normal words ("ass" in "classic"); those only count
-- when a whole part of the name is that word ("ass", "big_ass", "4ss.king").
-- The game keeps the same starter list (services/name_filter.gd) to warn while
-- typing; a test checks the two lists match.
--
-- How a name is checked: lower case; a look-alike digit standing alone becomes
-- a letter (0 o, 1 i, 3 e, 4 a, 5 s, 7 t; "17" stays a number); the name is also checked with repeated letters
-- squashed ("fuuuck"), the banned words never are ("kkk" stays "kkk").
-- Then: any non-whole word anywhere in the letters, or a whole word equal to a
-- part between dots, underscores or other digits, or to the whole name.

create table if not exists public.banned_words (
  word text primary key check (word ~ '^[a-z]{2,32}$'),
  whole_only boolean not null default false
);
alter table public.banned_words enable row level security;

insert into public.banned_words (word, whole_only) values
  ('fuck', false), ('shit', false), ('cunt', false), ('bitch', false), ('whore', false),
  ('slut', false), ('wank', false), ('pussy', false), ('penis', false), ('vagina', false),
  ('porn', false), ('rapist', false), ('nigger', false), ('nigga', false), ('faggot', false),
  ('retard', false), ('tranny', false), ('nazi', false), ('hitler', false), ('kkk', false),
  ('kanker', false), ('tering', false), ('tyfus', false), ('hoer', false), ('klootzak', false),
  ('flikker', false), ('neuk', false), ('mongool', false), ('godver', false),
  ('ass', true), ('arse', true), ('dick', true), ('cock', true), ('twat', true),
  ('prick', true), ('cum', true), ('rape', true), ('fag', true), ('anal', true),
  ('kike', true), ('spic', true), ('chink', true), ('kut', true), ('lul', true),
  ('pik', true), ('sex', true), ('tit', true), ('tits', true)
on conflict (word) do nothing;

-- "aaab" -> "ab".
create or replace function public.spikey_collapse(p_text text) returns text
language sql immutable as $$
  select regexp_replace(p_text, '(.)\1+', '\1', 'g')
$$;

-- A look-alike digit standing alone becomes its letter ("sh1t", "4ss"); a number
-- such as "17" stays digits, so "SwiftDash17" is not read as "...dashit".
create or replace function public.spikey_look_alikes(p_text text) returns text
language plpgsql immutable as $$
declare
  v_in text := lower(coalesce(p_text, ''));
  v_out text := '';
  v_c text;
begin
  for i in 1 .. length(v_in) loop
    v_c := substr(v_in, i, 1);
    if substr(v_in, i - 1, 1) !~ '[0-9]' and substr(v_in, i + 1, 1) !~ '[0-9]' then
      v_c := translate(v_c, '013457', 'oieast');
    end if;
    v_out := v_out || v_c;
  end loop;
  return v_out;
end
$$;

create or replace function public.spikey_name_allowed(p_name text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  v_text text := spikey_look_alikes(p_name);
  v_flat text := regexp_replace(v_text, '[^a-z]', '', 'g');
  -- The name as typed and with repeats squashed; banned words stay as written.
  v_flats text[] := array[v_flat, spikey_collapse(v_flat)];
  v_parts text[];
begin
  select coalesce(array_agg(part) || array_agg(spikey_collapse(part)), '{}') into v_parts
  from regexp_split_to_table(v_text, '[^a-z]+') as part
  where part <> '';
  return not exists (
    select 1 from banned_words b
    where (not b.whole_only and (position(b.word in v_flats[1]) > 0
                                 or position(b.word in v_flats[2]) > 0))
       or (b.whole_only and (b.word = any(v_parts) or b.word = any(v_flats)))
  );
end
$$;

-- Same as before, but a name that breaks the rules or the filter is ignored here
-- (the player keeps their old or default name), so a run is never lost over it.
create or replace function public.spikey_ensure_player(p_name text, p_flyer text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_flyer text := coalesce(nullif(left(coalesce(p_flyer, ''), 32), ''), 'buzz');
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  if v_name is not null
     and (v_name !~ '^[A-Za-z0-9._]{3,14}$' or not spikey_name_allowed(v_name)) then
    v_name := null;
  end if;
  insert into players (id, name, flyer)
  values (auth.uid(), coalesce(v_name, 'Flyer' || left(md5(auth.uid()::text), 4)), v_flyer)
  on conflict (id) do update
    set name = coalesce(v_name, players.name),
        flyer = excluded.flyer,
        updated_at = now();
end
$$;

-- Picking a name says no out loud, so the game can ask for another.
create or replace function public.set_player(p_name text, p_flyer text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(p_name, '') !~ '^[A-Za-z0-9._]{3,14}$' then
    raise exception 'invalid name';
  end if;
  if not spikey_name_allowed(p_name) then
    raise exception 'name not allowed';
  end if;
  perform spikey_ensure_player(p_name, p_flyer);
end
$$;

-- Clean up names already taken before the filter.
update public.players set name = 'Flyer' || left(md5(id::text), 4)
where not public.spikey_name_allowed(name);

revoke all on function public.spikey_name_allowed(text) from public, anon, authenticated;
revoke all on function public.spikey_collapse(text) from public, anon, authenticated;
revoke all on function public.spikey_look_alikes(text) from public, anon, authenticated;
