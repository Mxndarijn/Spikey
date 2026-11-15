//! `flapjaw-server`: migrates the database, then serves the game and runs the
//! checker and the push sender in the background.
//!
//!   flapjaw-server            serve (the default)
//!   flapjaw-server migrate    apply the migrations and stop (the deploy Job)
//!   flapjaw-server check      one checker round and stop

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use flapjaw_server::app::{self, AppState};
use flapjaw_server::config::Config;
use flapjaw_server::limits::Limits;
use flapjaw_server::{db, push, verify};
use tokio::sync::Notify;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .init();
    let config = match Config::from_env() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(2);
        }
    };
    let pool = db::connect(&config.database_url).await.unwrap_or_else(|e| {
        eprintln!("can't reach the database: {e}");
        std::process::exit(1);
    });
    let mode = std::env::args().nth(1).unwrap_or_default();
    let applied = db::migrate(&pool).await.unwrap_or_else(|e| {
        eprintln!("migration failed: {e}");
        std::process::exit(1);
    });
    tracing::info!("database ready ({} migrations applied now)", applied.len());
    match mode.as_str() {
        "migrate" => return,
        "check" => {
            let n = verify::round(&pool).await.unwrap_or(0);
            println!("checked {n} runs");
            return;
        }
        _ => {}
    }

    let new_run = Arc::new(Notify::new());
    spawn_checker(pool.clone(), new_run.clone(), config.verify_every_s);
    if let Some(account) = push::parse_account(&config.firebase_service_account) {
        if let Err(e) = push::register_sender(&pool).await {
            tracing::warn!("couldn't register the push sender: {e}");
        }
        spawn_push(pool.clone(), account, config.push_every_s);
    } else {
        tracing::info!("no FIREBASE_SERVICE_ACCOUNT: board alerts are not sent");
    }

    let listen = config.listen.clone();
    let state = Arc::new(AppState { pool, config, limits: Limits::new(), new_run });
    let listener = tokio::net::TcpListener::bind(&listen).await.unwrap_or_else(|e| {
        eprintln!("can't listen on {listen}: {e}");
        std::process::exit(1);
    });
    tracing::info!("listening on {listen}");
    axum::serve(listener, app::router(state).into_make_service_with_connect_info::<SocketAddr>())
        .with_graceful_shutdown(shutdown())
        .await
        .unwrap();
}

/// Checks runs as they arrive, and every few seconds as a safety net.
fn spawn_checker(pool: sqlx::PgPool, new_run: Arc<Notify>, every_s: u64) {
    tokio::spawn(async move {
        loop {
            match verify::round(&pool).await {
                Ok(n) if n > 0 => tracing::info!("checked {n} runs"),
                Ok(_) => {}
                Err(e) => tracing::warn!("checker round failed: {e}"),
            }
            tokio::select! {
                _ = new_run.notified() => {}
                _ = tokio::time::sleep(Duration::from_secs(every_s.max(1))) => {}
            }
        }
    });
}

fn spawn_push(pool: sqlx::PgPool, account: push::Account, every_s: u64) {
    tokio::spawn(async move {
        let http = reqwest::Client::new();
        loop {
            match push::round(&pool, &http, &account).await {
                Ok((0, 0)) => {}
                Ok((sent, failed)) => tracing::info!("board alerts: {sent} sent, {failed} failed"),
                Err(e) => tracing::warn!("push round failed: {e}"),
            }
            tokio::time::sleep(Duration::from_secs(every_s.max(5))).await;
        }
    });
}

/// Ctrl+C, or SIGTERM from Kubernetes when a pod is replaced.
async fn shutdown() {
    #[cfg(unix)]
    {
        let mut term = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()).unwrap();
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {}
            _ = term.recv() => {}
        }
    }
    #[cfg(not(unix))]
    {
        let _ = tokio::signal::ctrl_c().await;
    }
}
