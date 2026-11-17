//! The database: the pool and the migrations.
//!
//! Migrations run in order and once each, under an advisory lock (two servers
//! starting at once never both migrate). First the platform stand-ins
//! (`migrations/0001_platform.sql`), then the game's rules (`migrations/2026*.sql`,
//! written for Supabase before this server existed and kept as they are,
//! covered by `tools/db_test.ps1`), then the server's own (`migrations/0100_*`).
//! Applied migrations are remembered by file name, so a file is never renamed.
//! They are compiled into the binary, so an image always carries its schema.

use sqlx::postgres::{PgPool, PgPoolOptions};
use sqlx::Executor;

pub struct Migration {
    pub name: &'static str,
    pub sql: &'static str,
}

macro_rules! game {
    ($file:literal) => {
        Migration { name: $file, sql: include_str!(concat!("../migrations/", $file)) }
    };
}

/// Every migration, in the order they run. A new migration file must be
/// added here too (tests check the list matches the folder).
pub const MIGRATIONS: &[Migration] = &[
    Migration { name: "0001_platform.sql", sql: include_str!("../migrations/0001_platform.sql") },
    game!("20261108180000_leaderboards.sql"),
    game!("20261108200000_run_loadout.sql"),
    game!("20261108210000_name_filter.sql"),
    game!("20261109120000_verified_runs.sql"),
    game!("20261109210000_wake_checker.sql"),
    game!("20261110090000_revives.sql"),
    game!("20261110095000_board_plates.sql"),
    game!("20261110100000_diamonds.sql"),
    game!("20261110110000_push_alerts.sql"),
    game!("20261110120000_wake_sender.sql"),
    game!("20261110130000_test_push.sql"),
    game!("20261110140000_spend_requests.sql"),
    game!("20261110150000_profiles.sql"),
    game!("20261110160000_paid_items.sql"),
    game!("20261111100000_earn_status.sql"),
    game!("20261113120000_reset_boards.sql"),
    game!("20261113130000_daily_run.sql"),
    game!("20261114120000_score_ladder.sql"),
    Migration { name: "0100_backend.sql", sql: include_str!("../migrations/0100_backend.sql") },
    Migration { name: "0110_battles.sql", sql: include_str!("../migrations/0110_battles.sql") },
    Migration { name: "0111_wins_boards.sql", sql: include_str!("../migrations/0111_wins_boards.sql") },
    Migration { name: "0112_battle_bots.sql", sql: include_str!("../migrations/0112_battle_bots.sql") },
    Migration { name: "0113_duel.sql", sql: include_str!("../migrations/0113_duel.sql") },
    Migration { name: "0114_bot_levels.sql", sql: include_str!("../migrations/0114_bot_levels.sql") },
    Migration { name: "0115_versions.sql", sql: include_str!("../migrations/0115_versions.sql") },
    Migration { name: "0116_push_data.sql", sql: include_str!("../migrations/0116_push_data.sql") },
    Migration { name: "0117_shared_ip.sql", sql: include_str!("../migrations/0117_shared_ip.sql") },
    Migration { name: "0118_battle_paused.sql", sql: include_str!("../migrations/0118_battle_paused.sql") },
];

/// Some lock number only the migrator uses.
const MIGRATE_LOCK: i64 = 0x464c_4150_4a41;

pub async fn connect(url: &str) -> Result<PgPool, sqlx::Error> {
    PgPoolOptions::new().max_connections(10).connect(url).await
}

/// The text to run for a migration: the game's migrations create pg_net (a
/// Supabase extension), and the platform migration stands in for it.
pub fn prepared(sql: &str) -> String {
    sql.replace("create extension if not exists pg_net;", "")
}

/// Applies every migration not applied yet. Returns the names it applied.
pub async fn migrate(pool: &PgPool) -> Result<Vec<String>, sqlx::Error> {
    let mut conn = pool.acquire().await?;
    sqlx::query("select pg_advisory_lock($1)").bind(MIGRATE_LOCK).execute(&mut *conn).await?;
    let result = migrate_locked(&mut conn).await;
    sqlx::query("select pg_advisory_unlock($1)").bind(MIGRATE_LOCK).execute(&mut *conn).await?;
    result
}

async fn migrate_locked(conn: &mut sqlx::PgConnection) -> Result<Vec<String>, sqlx::Error> {
    conn.execute(
        "create table if not exists public.server_migrations (
           name text primary key, applied_at timestamptz not null default now())",
    )
    .await?;
    let done: Vec<String> =
        sqlx::query_scalar("select name from public.server_migrations").fetch_all(&mut *conn).await?;
    let mut applied = Vec::new();
    for m in MIGRATIONS {
        if done.iter().any(|d| d == m.name) {
            continue;
        }
        let mut tx = sqlx::Connection::begin(&mut *conn).await?;
        // Simple protocol: a migration file is many statements.
        tx.execute(prepared(m.sql).as_str()).await?;
        sqlx::query("insert into public.server_migrations (name) values ($1)").bind(m.name).execute(&mut *tx).await?;
        tx.commit().await?;
        tracing::info!("applied migration {}", m.name);
        applied.push(m.name.to_string());
    }
    Ok(applied)
}
