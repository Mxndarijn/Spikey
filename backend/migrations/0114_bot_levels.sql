-- The bot levels' first guess from the calibration (fastsim-rs
-- battlebot-calibrate, 60 seeds, 2026-11-17): the levels' median scores are
-- 20, 23, 32, 38, 54, 129, 157 and 157, and a bot wins about half its rounds
-- against a player whose typical score is its median. So a player is matched
-- to the level whose median is nearest their own; level 8 (beast) is reached
-- only by beating level 7 by 3 or more (spikey_battle_ended).
create or replace function public.spikey_bot_level_guess(p_player uuid) returns integer
language sql stable as $$
  select case
    when m is null or m < 21.5 then 1
    when m < 27.5 then 2
    when m < 35 then 3
    when m < 46 then 4
    when m < 91.5 then 5
    when m < 143 then 6
    else 7 end
  from (
    select percentile_cont(0.5) within group (order by score) as m
    from (
      select score from public.runs where player_id = p_player and status = 'ok'
      order by id desc limit 20
    ) r
  ) x
$$;
revoke all on function public.spikey_bot_level_guess(uuid) from public, anon, authenticated;
