-- Battle is paused (the user, 2026-11-17): the app hides it, and the server
-- refuses new battles and nudges (config.battle_paused, app.rs PAUSED_OPS) and
-- sends no battle alerts (push.rs held). Here: no bot takes a new random
-- battle (a bot wait below 0 is off; worker_set_bot_wait(600) turns it back on).
-- Bot battles already running go on. The tables and ops stay, so phones that
-- still show Battle keep working.
insert into public.worker_settings (key, value) values ('bot_wait_s', '-1')
on conflict (key) do update set value = excluded.value, updated_at = now();
