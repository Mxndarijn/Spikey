//! The Battle bots' worker (docs/DUEL_MODE.md, section 6): gives a bot to
//! random battles nobody took in time (worker_assign_bots, migrations/
//! 0112_battle_bots.sql) and plays the bot turns that are due, through the
//! same battle_* operations a phone calls, signed in as the bot player.
//!
//! A run itself comes from a `Runner`: in the battle-bot pod the FastSim-RS
//! human-model bot (`fastsim-rs battlebot`, screen-only sight, the human
//! thumb), in tests a stand-in. The bot never reads its rival's run.

use serde_json::{json, Value};
use sim::sim_config::SimConfig;
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::ApiResult;
use crate::rpc;

/// One bot run.
#[derive(Clone, Debug, PartialEq)]
pub struct BotRun {
    pub taps: Vec<i64>,
    pub score: i64,
    pub coins: i64,
    pub end_tick: i64,
}

/// Plays one run: (seed, season, level 1..8, bot seed for its tap noise).
pub type Runner = dyn Fn(i64, i64, i64, i64) -> Result<BotRun, String> + Send + Sync;

/// The FastSim-RS bot as a separate program (`fastsim-rs battlebot`), so the
/// server crate doesn't carry the planner.
pub fn fastsim_runner(bin: String) -> Box<Runner> {
    Box::new(move |seed, season, level, bot_seed| {
        let out = std::process::Command::new(&bin)
            .args([
                "battlebot",
                "--seed",
                &seed.to_string(),
                "--season",
                &season.to_string(),
                "--level",
                &level.to_string(),
                "--bot-seed",
                &bot_seed.to_string(),
            ])
            .output()
            .map_err(|e| format!("{bin}: {e}"))?;
        if !out.status.success() {
            return Err(format!("{bin} failed: {}", String::from_utf8_lossy(&out.stderr)));
        }
        parse_run(&String::from_utf8_lossy(&out.stdout))
    })
}

/// The battlebot mode's one line of JSON.
pub fn parse_run(text: &str) -> Result<BotRun, String> {
    let v: Value = serde_json::from_str(text.trim()).map_err(|e| format!("bot output: {e}"))?;
    let int = |k: &str| v[k].as_i64().ok_or_else(|| format!("bot output has no {k}"));
    let taps = v["taps"].as_array().ok_or("bot output has no taps")?.iter().filter_map(|t| t.as_i64()).collect();
    Ok(BotRun { taps, score: int("score")?, coins: int("coins")?, end_tick: int("end_tick")? })
}

async fn op(pool: &PgPool, bot: Uuid, name: &str, body: Value) -> ApiResult<Value> {
    let op = rpc::find(name).expect("a battle operation");
    rpc::call(pool, bot, op, &body).await
}

/// Plays a bot's whole turn in one battle: the round it answers, then the one it
/// opens. Returns the runs sent.
pub async fn play_turn(pool: &PgPool, runner: &Runner, battle: i64, bot: Uuid, level: i64) -> Result<usize, String> {
    let name: String = sqlx::query_scalar("select name from public.players where id = $1")
        .bind(bot)
        .fetch_one(pool)
        .await
        .map_err(|e| e.to_string())?;
    let version = SimConfig::GAMEPLAY_VERSION;
    let mut sent = 0;
    for _ in 0..4 {
        let view = op(pool, bot, "battle_get", json!({"p_battle": battle})).await.map_err(|e| e.message)?;
        let Some(round) = view["play"]["round"].as_i64() else { break };
        let start = op(
            pool,
            bot,
            "battle_start_run",
            json!({"p_battle": battle, "p_round": round, "p_gameplay_version": version}),
        )
        .await
        .map_err(|e| e.message)?;
        if start["lost"] == json!(true) || start["redealt"] == json!(true) || start["seed"].is_null() {
            continue;
        }
        let (seed, season) = (start["seed"].as_i64().unwrap_or(0), start["season"].as_i64().unwrap_or(-1));
        let bot_seed = battle.wrapping_mul(1000) + round;
        let run = runner(seed, season, level, bot_seed)?;
        op(
            pool,
            bot,
            "battle_submit",
            json!({
                "p_battle": battle, "p_round": round, "p_name": name, "p_flyer": "buzz",
                "p_score": run.score, "p_gameplay_version": version, "p_seed": seed, "p_taps": run.taps,
                "p_season": season, "p_coins": run.coins, "p_end_tick": run.end_tick,
                "p_loadout": {"flyer": "buzz"},
            }),
        )
        .await
        .map_err(|e| e.message)?;
        sent += 1;
    }
    Ok(sent)
}

/// One worker round: bots for random battles waiting past the bot wait, then
/// every due bot turn. Returns (bots assigned, runs sent).
pub async fn round(pool: &PgPool, runner: &Runner) -> Result<(i32, usize), sqlx::Error> {
    let assigned: i32 = sqlx::query_scalar("select public.worker_assign_bots(20)").fetch_one(pool).await?;
    let due: Value = sqlx::query_scalar("select public.worker_bot_turns(20)").fetch_one(pool).await?;
    let mut sent = 0;
    for t in due.as_array().cloned().unwrap_or_default() {
        let (Some(battle), Some(bot)) = (t["battle"].as_i64(), t["bot"].as_str().and_then(|s| Uuid::parse_str(s).ok()))
        else {
            continue;
        };
        let level = t["level"].as_i64().unwrap_or(3);
        match play_turn(pool, runner, battle, bot, level).await {
            Ok(n) => sent += n,
            Err(e) => {
                tracing::warn!("bot turn in battle {battle} failed: {e}");
                // Try again later rather than every round.
                sqlx::query("update public.battles set bot_due_at = now() + interval '5 minutes' where id = $1")
                    .bind(battle)
                    .execute(pool)
                    .await?;
            }
        }
    }
    Ok((assigned, sent))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_bot_programs_line_is_read() {
        let r = parse_run(r#"{"taps": [3, 20], "score": 4, "coins": 1, "end_tick": 300, "level": 2}"#).unwrap();
        assert_eq!(r, BotRun { taps: vec![3, 20], score: 4, coins: 1, end_tick: 300 });
        assert!(parse_run("oops").is_err());
        assert!(parse_run(r#"{"taps": []}"#).is_err());
    }
}
