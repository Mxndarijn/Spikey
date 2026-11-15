//! Sign-in (the game's FlapjawClient, services/flapjaw_client.gd).
//!
//! Every player has a device key ("Fj-" + 64 hex, made on the phone) that the
//! server keeps only as a sha-256 hash. A session is an access token (an hour)
//! and a refresh token that changes every time it is used; both are random
//! and also stored only as hashes. A transfer revokes the moved player's old
//! keys and sessions with the reason `moved`, and the old phone hears
//! `401 account_moved` on its next request.

use axum::http::{HeaderMap, StatusCode};
use rand::RngCore;
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::{ApiError, ApiResult};

pub const MOVED: &str = "moved";

pub fn sha256(text: &str) -> Vec<u8> {
    Sha256::digest(text.as_bytes()).to_vec()
}

/// A random token with a short prefix that says what it is.
pub fn new_token(prefix: &str) -> String {
    let mut bytes = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut bytes);
    format!("{prefix}{}", hex::encode(bytes))
}

/// "Fj-" and 64 lower-case hex characters, like the game makes them.
pub fn is_device_key(key: &str) -> bool {
    key.len() == 67
        && key.starts_with("Fj-")
        && key[3..].bytes().all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
}

/// A new session for `player`: the answer the client keeps.
pub async fn new_session<'e, E>(db: E, player: Uuid, access_ttl: i64, refresh_ttl: i64) -> ApiResult<Value>
where
    E: sqlx::PgExecutor<'e>,
{
    let access = new_token("fa_");
    let refresh = new_token("fr_");
    sqlx::query(
        "insert into backend.sessions (player_id, access_hash, access_expires, refresh_hash, refresh_expires)
         values ($1, $2, now() + make_interval(secs => $3), $4, now() + make_interval(secs => $5))",
    )
    .bind(player)
    .bind(sha256(&access))
    .bind(access_ttl as f64)
    .bind(sha256(&refresh))
    .bind(refresh_ttl as f64)
    .execute(db)
    .await?;
    Ok(session_answer(player, &access, &refresh, access_ttl))
}

fn session_answer(player: Uuid, access: &str, refresh: &str, ttl: i64) -> Value {
    json!({
        "player_id": player.to_string(),
        "access_token": access,
        "refresh_token": refresh,
        "expires_in": ttl,
    })
}

#[derive(Deserialize)]
pub struct AnonBody {
    pub device_key: String,
}

/// A new player with this phone's device key. The same key again (the answer
/// to the first try got lost) signs in as the player it made.
pub async fn anon(pool: &PgPool, body: AnonBody, access_ttl: i64, refresh_ttl: i64) -> ApiResult<Value> {
    if !is_device_key(&body.device_key) {
        return Err(ApiError::bad("not a device key"));
    }
    let hash = sha256(&body.device_key);
    let mut tx = pool.begin().await?;
    let known: Option<(Uuid, Option<String>)> =
        sqlx::query_as("select player_id, revoked_reason from backend.devices where key_hash = $1 for update")
            .bind(&hash)
            .fetch_optional(&mut *tx)
            .await?;
    let player = match known {
        Some((_, Some(reason))) if reason == MOVED => return Err(ApiError::unauthorized("account_moved")),
        Some((_, Some(_))) => return Err(ApiError::unauthorized("unknown_key")),
        Some((player, None)) => player,
        None => {
            let player = Uuid::new_v4();
            sqlx::query("insert into auth.users (id) values ($1)").bind(player).execute(&mut *tx).await?;
            sqlx::query("insert into backend.devices (key_hash, player_id) values ($1, $2)")
                .bind(&hash)
                .bind(player)
                .execute(&mut *tx)
                .await?;
            player
        }
    };
    let answer = new_session(&mut *tx, player, access_ttl, refresh_ttl).await?;
    tx.commit().await?;
    Ok(answer)
}

#[derive(Deserialize)]
pub struct RefreshBody {
    pub refresh_token: String,
}

/// A new access token for a refresh token; the refresh token changes too.
pub async fn refresh(pool: &PgPool, body: RefreshBody, access_ttl: i64, refresh_ttl: i64) -> ApiResult<Value> {
    let row: Option<(i64, Uuid, bool, Option<String>)> = sqlx::query_as(
        "select id, player_id, refresh_expires > now(), revoked_reason
         from backend.sessions where refresh_hash = $1",
    )
    .bind(sha256(&body.refresh_token))
    .fetch_optional(pool)
    .await?;
    let Some((id, player, alive, revoked)) = row else {
        return Err(ApiError::unauthorized("session_gone"));
    };
    match revoked.as_deref() {
        Some(MOVED) => return Err(ApiError::unauthorized("account_moved")),
        Some(_) => return Err(ApiError::unauthorized("session_gone")),
        None if !alive => return Err(ApiError::unauthorized("session_gone")),
        None => {}
    }
    let access = new_token("fa_");
    let next = new_token("fr_");
    // Only one use of a refresh token wins; a second one finds it changed.
    let changed = sqlx::query(
        "update backend.sessions
         set access_hash = $2, access_expires = now() + make_interval(secs => $3),
             refresh_hash = $4, refresh_expires = now() + make_interval(secs => $5)
         where id = $1 and refresh_hash = $6 and revoked_at is null",
    )
    .bind(id)
    .bind(sha256(&access))
    .bind(access_ttl as f64)
    .bind(sha256(&next))
    .bind(refresh_ttl as f64)
    .bind(sha256(&body.refresh_token))
    .execute(pool)
    .await?;
    if changed.rows_affected() == 0 {
        return Err(ApiError::unauthorized("session_gone"));
    }
    Ok(session_answer(player, &access, &next, access_ttl))
}

#[derive(Deserialize)]
pub struct DeviceBody {
    pub player_id: String,
    pub device_key: String,
}

/// Signs a phone in with its device key (a restored backup, a dead refresh token).
pub async fn device(pool: &PgPool, body: DeviceBody, access_ttl: i64, refresh_ttl: i64) -> ApiResult<Value> {
    let player = Uuid::parse_str(&body.player_id).map_err(|_| ApiError::unauthorized("unknown_key"))?;
    if !is_device_key(&body.device_key) {
        return Err(ApiError::unauthorized("unknown_key"));
    }
    let revoked: Option<Option<String>> =
        sqlx::query_scalar("select revoked_reason from backend.devices where key_hash = $1 and player_id = $2")
            .bind(sha256(&body.device_key))
            .bind(player)
            .fetch_optional(pool)
            .await?;
    match revoked {
        None => Err(ApiError::unauthorized("unknown_key")),
        Some(Some(r)) if r == MOVED => Err(ApiError::unauthorized("account_moved")),
        Some(Some(_)) => Err(ApiError::unauthorized("unknown_key")),
        Some(None) => new_session(pool, player, access_ttl, refresh_ttl).await,
    }
}

/// The player behind a request's `Authorization: Bearer <access token>`.
pub async fn player_of(pool: &PgPool, headers: &HeaderMap) -> ApiResult<Uuid> {
    let token = headers
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "))
        .ok_or_else(|| ApiError::unauthorized("session_gone"))?;
    let row: Option<(Uuid, bool, Option<String>)> = sqlx::query_as(
        "select player_id, access_expires > now(), revoked_reason from backend.sessions where access_hash = $1",
    )
    .bind(sha256(token))
    .fetch_optional(pool)
    .await?;
    match row {
        None => Err(ApiError::unauthorized("session_gone")),
        Some((_, _, Some(r))) if r == MOVED => Err(ApiError::unauthorized("account_moved")),
        Some((_, _, Some(_))) => Err(ApiError::unauthorized("session_gone")),
        Some((_, false, None)) => Err(ApiError::unauthorized("token_expired")),
        Some((player, true, None)) => Ok(player),
    }
}

/// 426 for an app older than the server accepts (the game asks to update).
pub fn check_version(headers: &HeaderMap, min: i64) -> ApiResult<()> {
    let api: i64 =
        headers.get("x-flapjaw-api").and_then(|v| v.to_str().ok()).and_then(|v| v.trim().parse().ok()).unwrap_or(0);
    if api < min {
        return Err(ApiError::new(
            StatusCode::UPGRADE_REQUIRED,
            "update_required",
            format!("this app speaks version {api}, the server needs {min}"),
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn device_keys_look_like_the_games() {
        let ok = format!("Fj-{}", "0a".repeat(32));
        assert!(is_device_key(&ok));
        assert!(!is_device_key(&format!("Fj-{}", "0A".repeat(32))), "lower case only");
        assert!(!is_device_key(&ok[..66]));
        assert!(!is_device_key(""));
    }

    #[test]
    fn tokens_are_long_random_and_prefixed() {
        let a = new_token("fa_");
        assert_eq!(a.len(), 67);
        assert!(a.starts_with("fa_"));
        assert_ne!(a, new_token("fa_"));
    }

    #[test]
    fn old_apps_are_asked_to_update() {
        let mut h = HeaderMap::new();
        assert_eq!(check_version(&h, 1).unwrap_err().status, StatusCode::UPGRADE_REQUIRED);
        h.insert("x-flapjaw-api", "1".parse().unwrap());
        assert!(check_version(&h, 1).is_ok());
        assert!(check_version(&h, 2).is_err());
    }
}
