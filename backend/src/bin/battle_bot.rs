//! `battle-bot`: the Battle bots' worker (docs/DUEL_MODE.md, section 6), its
//! own pod beside the server (deploy/base/app/battle-bot.yaml). Every
//! BOT_EVERY_S seconds (30) it gives bots to random battles nobody took within
//! the bot wait and plays the bot turns that are due, each run made by
//! FASTSIM_BIN (`fastsim-rs battlebot`). The server migrates the database; this
//! only connects to it.

use std::time::Duration;

use flapjaw_server::{bot, db};

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .init();
    let Ok(url) = std::env::var("DATABASE_URL") else {
        eprintln!("DATABASE_URL is not set");
        std::process::exit(2);
    };
    let every: u64 = std::env::var("BOT_EVERY_S").ok().and_then(|v| v.parse().ok()).unwrap_or(30);
    let bin = std::env::var("FASTSIM_BIN").unwrap_or_else(|_| "fastsim-rs".into());
    let pool = db::connect(&url).await.unwrap_or_else(|e| {
        eprintln!("can't reach the database: {e}");
        std::process::exit(1);
    });
    let runner = bot::fastsim_runner(bin);
    tracing::info!("battle bots: a round every {every} s");
    loop {
        match bot::round(&pool, runner.as_ref()).await {
            Ok((0, 0)) => {}
            Ok((assigned, sent)) => tracing::info!("battle bots: {assigned} battles taken, {sent} runs played"),
            Err(e) => tracing::warn!("battle bot round failed: {e}"),
        }
        tokio::time::sleep(Duration::from_secs(every.max(5))).await;
    }
}
