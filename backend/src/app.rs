//! The HTTP routes.
//!
//! - `GET  /v1/ping`, `GET /healthz`: alive, which build, which gameplay version.
//! - `POST /v1/auth/anon | refresh | device`: sign-in (auth.rs).
//! - `POST /v1/transfer/create | cancel | preview | redeem`: phone moves (transfer.rs).
//! - `GET  /v1/duel/ws`: a live Duel over a WebSocket (duel_ws.rs).
//! - `POST /v1/<op>`: the game's operations (rpc.rs).
//!
//! Every /v1 request says which app protocol it speaks (`X-Flapjaw-Api`); an
//! older one than MIN_API_VERSION gets 426 and the game asks to update.

use std::net::SocketAddr;
use std::sync::Arc;

use axum::extract::{ConnectInfo, Path, State};
use axum::http::HeaderMap;
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::PgPool;
use tokio::sync::Notify;

use crate::auth;
use crate::config::Config;
use crate::error::{ApiError, ApiResult};
use crate::limits::Limits;
use crate::rpc;
use crate::transfer;

pub struct AppState {
    pub pool: PgPool,
    pub config: Config,
    pub limits: Limits,
    /// Wakes the checker when a run arrives.
    pub new_run: Arc<Notify>,
}

pub type Shared = Arc<AppState>;

pub fn router(state: Shared) -> Router {
    Router::new()
        .route("/healthz", get(ping))
        .route("/v1/ping", get(ping))
        .route("/v1/auth/anon", post(auth_anon))
        .route("/v1/auth/refresh", post(auth_refresh))
        .route("/v1/auth/device", post(auth_device))
        .route("/v1/transfer/create", post(transfer_create))
        .route("/v1/transfer/cancel", post(transfer_cancel))
        .route("/v1/transfer/preview", post(transfer_preview))
        .route("/v1/transfer/redeem", post(transfer_redeem))
        .route("/v1/duel/ws", get(crate::duel_ws::upgrade))
        .route("/v1/{op}", post(operation))
        .with_state(state)
}

/// The caller's address: the first X-Forwarded-For hop behind Traefik, else the socket.
pub fn client_ip(state: &AppState, headers: &HeaderMap, peer: Option<SocketAddr>) -> String {
    if state.config.trust_proxy {
        if let Some(first) =
            headers.get("x-forwarded-for").and_then(|v| v.to_str().ok()).and_then(|v| v.split(',').next())
        {
            return first.trim().to_string();
        }
    }
    peer.map(|p| p.ip().to_string()).unwrap_or_else(|| "unknown".into())
}

async fn ping(State(s): State<Shared>) -> ApiResult<Json<Value>> {
    let db: i32 = sqlx::query_scalar("select 1").fetch_one(&s.pool).await?;
    Ok(Json(json!({
        "ok": db == 1,
        "version": s.config.git_sha,
        "gameplay_version": sim::sim_config::SimConfig::GAMEPLAY_VERSION,
        "min_api_version": s.config.min_api_version,
    })))
}

async fn auth_anon(
    State(s): State<Shared>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Json(body): Json<auth::AnonBody>,
) -> ApiResult<Json<Value>> {
    auth::check_version(&headers, s.config.min_api_version)?;
    let ip = client_ip(&s, &headers, Some(addr));
    if !s.limits.signup_ip.allow(&ip) {
        return Err(ApiError::too_many());
    }
    Ok(Json(auth::anon(&s.pool, body, s.config.access_ttl_s, s.config.refresh_ttl_s).await?))
}

async fn auth_refresh(
    State(s): State<Shared>,
    headers: HeaderMap,
    Json(body): Json<auth::RefreshBody>,
) -> ApiResult<Json<Value>> {
    auth::check_version(&headers, s.config.min_api_version)?;
    Ok(Json(auth::refresh(&s.pool, body, s.config.access_ttl_s, s.config.refresh_ttl_s).await?))
}

async fn auth_device(
    State(s): State<Shared>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Json(body): Json<auth::DeviceBody>,
) -> ApiResult<Json<Value>> {
    auth::check_version(&headers, s.config.min_api_version)?;
    let ip = client_ip(&s, &headers, Some(addr));
    if !s.limits.device_ip.allow(&ip) {
        return Err(ApiError::too_many());
    }
    Ok(Json(auth::device(&s.pool, body, s.config.access_ttl_s, s.config.refresh_ttl_s).await?))
}

async fn signed_in(s: &AppState, headers: &HeaderMap) -> ApiResult<uuid::Uuid> {
    auth::check_version(headers, s.config.min_api_version)?;
    auth::player_of(&s.pool, headers).await
}

async fn transfer_create(State(s): State<Shared>, headers: HeaderMap) -> ApiResult<Json<Value>> {
    let player = signed_in(&s, &headers).await?;
    Ok(Json(transfer::create(&s.pool, player).await?))
}

async fn transfer_cancel(State(s): State<Shared>, headers: HeaderMap) -> ApiResult<Json<Value>> {
    let player = signed_in(&s, &headers).await?;
    Ok(Json(transfer::cancel(&s.pool, player).await?))
}

#[derive(Deserialize)]
struct CodeBody {
    code: String,
    #[serde(default)]
    device_key: String,
}

/// Counts a code try against the player's and the address's limits.
fn code_try(s: &AppState, player: uuid::Uuid, ip: &str) -> ApiResult<()> {
    let p = s.limits.transfer_player.allow(&player.to_string());
    let i = s.limits.transfer_ip.allow(ip);
    if p && i {
        Ok(())
    } else {
        Err(ApiError::too_many())
    }
}

async fn transfer_preview(
    State(s): State<Shared>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Json(body): Json<CodeBody>,
) -> ApiResult<Json<Value>> {
    let player = signed_in(&s, &headers).await?;
    code_try(&s, player, &client_ip(&s, &headers, Some(addr)))?;
    Ok(Json(transfer::preview(&s.pool, player, &body.code).await?))
}

async fn transfer_redeem(
    State(s): State<Shared>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Json(body): Json<CodeBody>,
) -> ApiResult<Json<Value>> {
    let player = signed_in(&s, &headers).await?;
    let ip = client_ip(&s, &headers, Some(addr));
    code_try(&s, player, &ip)?;
    let c = &s.config;
    let answer =
        transfer::redeem(&s.pool, player, &body.code, &body.device_key, &ip, c.access_ttl_s, c.refresh_ttl_s).await?;
    Ok(Json(answer))
}

async fn operation(
    State(s): State<Shared>,
    Path(name): Path<String>,
    headers: HeaderMap,
    body: Option<Json<Value>>,
) -> ApiResult<Json<Value>> {
    auth::check_version(&headers, s.config.min_api_version)?;
    let op = rpc::find(&name).ok_or_else(|| ApiError::not_found(format!("no operation {name}")))?;
    let player = auth::player_of(&s.pool, &headers).await?;
    let body = body.map(|Json(v)| v).unwrap_or(Value::Null);
    let answer = rpc::call(&s.pool, player, op, &body).await?;
    if op.new_run {
        s.new_run.notify_one();
    }
    Ok(Json(answer))
}
