-- A diamond spend is charged once, however often the phone asks.
-- The phone sends a random request id with every spend. If the answer is lost
-- (no internet, timeout), it asks again with the same id; this migration
-- answers a repeat with the balance the first call left instead of charging
-- again. Calls without an id (older builds) work as before.

create table if not exists public.spend_requests (
  player_id uuid not null references public.players (id) on delete cascade,
  request uuid not null,
  -- The balance right after the spend: what a repeat of it answers.
  diamonds integer not null,
  created_at timestamptz not null default now(),
  primary key (player_id, request)
);

alter table public.spend_requests enable row level security;

drop function if exists public.spend_diamonds(integer, text, text);

create or replace function public.spend_diamonds(
  p_amount integer,
  p_reason text,
  p_ref text default '',
  p_request uuid default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_done integer;
  v_new integer;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;
  if p_amount is null or p_amount < 1 or p_amount > 10000 then
    raise exception 'invalid amount';
  end if;
  if p_reason is null or p_reason not in ('convert', 'item') then
    raise exception 'invalid reason';
  end if;
  if p_request is not null then
    select diamonds into v_done
    from spend_requests
    where player_id = v_uid and request = p_request;
    if found then
      return jsonb_build_object('diamonds', v_done, 'repeat', true);
    end if;
  end if;
  v_new := spikey_change_diamonds(v_uid, -p_amount, p_reason, p_ref);
  if p_request is not null then
    -- Two calls with one id at the same moment: the second fails here and
    -- its charge is rolled back with it.
    insert into spend_requests (player_id, request, diamonds)
    values (v_uid, p_request, v_new);
  end if;
  return jsonb_build_object('diamonds', v_new);
end
$$;

revoke all on function public.spend_diamonds(integer, text, text, uuid) from public, anon;
grant execute on function public.spend_diamonds(integer, text, text, uuid) to authenticated;
