//! Move to a new phone (docs/ACCOUNT_TRANSFER.md).
//!
//! The old phone asks for a code: 12 characters of Crockford base32 (60 random
//! bits), valid 24 hours and once, stored only as a hash. The new phone looks
//! at what would move (preview) and then takes it (redeem): in one transaction
//! the code is used, every session and device key of the player is revoked as
//! `moved`, and the new phone's key and session take their place. Nothing is
//! copied: everything is stored under the player id, so the new phone simply
//! becomes that player. Its own progress (its old anonymous player) is left
//! behind, never merged.

use rand::RngCore;
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

use crate::auth::{self, sha256, MOVED};
use crate::error::{ApiError, ApiResult};

/// Crockford's base32: no I, L, O or U.
const ALPHABET: &[u8; 32] = b"0123456789ABCDEFGHJKMNPQRSTVWXYZ";
pub const CODE_LEN: usize = 12;
pub const VALID_HOURS: i64 = 24;
pub const PER_DAY: i64 = 5;

/// A new random code, 12 characters (shown as XXXX-XXXX-XXXX).
pub fn new_code() -> String {
    let mut bytes = [0u8; 8];
    rand::thread_rng().fill_bytes(&mut bytes);
    let mut n = u64::from_le_bytes(bytes);
    (0..CODE_LEN)
        .map(|_| {
            let c = ALPHABET[(n & 31) as usize] as char;
            n >>= 5;
            c
        })
        .collect()
}

/// A typed code made comparable: upper case, without dashes or spaces, the
/// look-alikes read as Crockford says (O as 0, I and L as 1). None when it
/// can't be a code.
pub fn normalize(typed: &str) -> Option<String> {
    let mut out = String::new();
    for c in typed.chars() {
        let c = match c.to_ascii_uppercase() {
            '-' | ' ' => continue,
            'O' => '0',
            'I' | 'L' => '1',
            c => c,
        };
        if !ALPHABET.contains(&(c as u8)) || !c.is_ascii() {
            return None;
        }
        out.push(c);
    }
    (out.len() == CODE_LEN).then_some(out)
}

/// The old phone: a new code for its player (earlier unused codes stop working).
pub async fn create(pool: &PgPool, player: Uuid) -> ApiResult<Value> {
    let mut tx = pool.begin().await?;
    // One at a time per player, so the daily count can't be raced.
    sqlx::query("select pg_advisory_xact_lock(hashtext($1::text))").bind(player).execute(&mut *tx).await?;
    let today: i64 = sqlx::query_scalar(
        "select count(*) from backend.transfer_codes where player_id = $1 and created_at > now() - interval '1 day'",
    )
    .bind(player)
    .fetch_one(&mut *tx)
    .await?;
    if today >= PER_DAY {
        return Err(ApiError::too_many());
    }
    sqlx::query(
        "update backend.transfer_codes set cancelled_at = now()
         where player_id = $1 and used_at is null and cancelled_at is null",
    )
    .bind(player)
    .execute(&mut *tx)
    .await?;
    let code = new_code();
    let expires: chrono::DateTime<chrono::Utc> = sqlx::query_scalar(
        "insert into backend.transfer_codes (code_hash, player_id, expires_at)
         values ($1, $2, now() + make_interval(hours => $3)) returning expires_at",
    )
    .bind(sha256(&code))
    .bind(player)
    .bind(VALID_HOURS as i32)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(json!({"code": code, "expires_at": expires.timestamp(), "valid_hours": VALID_HOURS}))
}

/// The old phone: its open code stops working.
pub async fn cancel(pool: &PgPool, player: Uuid) -> ApiResult<Value> {
    let n = sqlx::query(
        "update backend.transfer_codes set cancelled_at = now()
         where player_id = $1 and used_at is null and cancelled_at is null",
    )
    .bind(player)
    .execute(pool)
    .await?
    .rows_affected();
    Ok(json!({"cancelled": n}))
}

/// The player a code would move, or why not.
async fn owner<'e, E: sqlx::PgExecutor<'e>>(db: E, code: &str, caller: Uuid, lock: bool) -> ApiResult<Uuid> {
    let code = normalize(code).ok_or_else(|| ApiError::bad("that is not a code"))?;
    let sql = format!(
        "select player_id, used_at is not null, cancelled_at is not null, expires_at < now()
         from backend.transfer_codes where code_hash = $1{}",
        if lock { " for update" } else { "" }
    );
    let row: Option<(Uuid, bool, bool, bool)> = sqlx::query_as(&sql).bind(sha256(&code)).fetch_optional(db).await?;
    match row {
        None => Err(ApiError::new(axum::http::StatusCode::NOT_FOUND, "unknown_code", "that code doesn't work")),
        Some((_, true, _, _)) => {
            Err(ApiError::new(axum::http::StatusCode::GONE, "code_used", "that code was already used"))
        }
        Some((_, _, true, _)) | Some((_, _, _, true)) => {
            Err(ApiError::new(axum::http::StatusCode::GONE, "code_expired", "that code has expired"))
        }
        Some((p, ..)) if p == caller => Err(ApiError::bad("this phone already is that player")),
        Some((p, ..)) => Ok(p),
    }
}

/// The new phone: what the code would move (screen 5 of the mockups).
pub async fn preview(pool: &PgPool, caller: Uuid, code: &str) -> ApiResult<Value> {
    let player = owner(pool, code, caller, false).await?;
    let mut summary: Value =
        sqlx::query_scalar("select backend.transfer_summary($1)").bind(player).fetch_one(pool).await?;
    let mine: Value = sqlx::query_scalar("select backend.transfer_summary($1)").bind(caller).fetch_one(pool).await?;
    summary["this_phone"] = mine;
    Ok(summary)
}

/// The new phone: becomes the code's player. Answers a session for it.
pub async fn redeem(
    pool: &PgPool,
    caller: Uuid,
    code: &str,
    device_key: &str,
    ip: &str,
    access_ttl: i64,
    refresh_ttl: i64,
) -> ApiResult<Value> {
    if !auth::is_device_key(device_key) {
        return Err(ApiError::bad("not a device key"));
    }
    let mut tx = pool.begin().await?;
    let player = owner(&mut *tx, code, caller, true).await?;
    let code = normalize(code).unwrap();
    sqlx::query(
        "update backend.transfer_codes set used_at = now(), used_by_player = $2, used_by_ip = $3 where code_hash = $1",
    )
    .bind(sha256(&code))
    .bind(caller)
    .bind(ip)
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "update backend.sessions set revoked_at = now(), revoked_reason = $2
         where player_id = $1 and revoked_at is null",
    )
    .bind(player)
    .bind(MOVED)
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "update backend.devices set revoked_at = now(), revoked_reason = $2
         where player_id = $1 and revoked_at is null",
    )
    .bind(player)
    .bind(MOVED)
    .execute(&mut *tx)
    .await?;
    // The new phone's key now belongs to the moved player; its old player
    // keeps nothing that signs in.
    sqlx::query(
        "update backend.sessions set revoked_at = now(), revoked_reason = 'left_behind'
         where player_id = $1 and revoked_at is null",
    )
    .bind(caller)
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "update backend.devices set revoked_at = now(), revoked_reason = 'left_behind'
         where player_id = $1 and revoked_at is null",
    )
    .bind(caller)
    .execute(&mut *tx)
    .await?;
    sqlx::query("insert into backend.devices (key_hash, player_id) values ($1, $2)")
        .bind(sha256(device_key))
        .bind(player)
        .execute(&mut *tx)
        .await?;
    sqlx::query("insert into backend.transfer_log (player_id, left_behind, ip) values ($1, $2, $3)")
        .bind(player)
        .bind(caller)
        .bind(ip)
        .execute(&mut *tx)
        .await?;
    let session = auth::new_session(&mut *tx, player, access_ttl, refresh_ttl).await?;
    tx.commit().await?;
    tracing::info!("player {player} moved to a new phone");
    Ok(session)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codes_are_twelve_crockford_characters() {
        for _ in 0..200 {
            let c = new_code();
            assert_eq!(c.len(), CODE_LEN);
            assert!(c.bytes().all(|b| ALPHABET.contains(&b)), "{c}");
            assert_eq!(normalize(&c).as_deref(), Some(c.as_str()));
        }
        assert_ne!(new_code(), new_code());
    }

    #[test]
    fn typed_codes_forgive_dashes_case_and_look_alikes() {
        assert_eq!(normalize("k7qf-3mzd-px9w").as_deref(), Some("K7QF3MZDPX9W"));
        assert_eq!(normalize("K7QF 3MZD PX9W").as_deref(), Some("K7QF3MZDPX9W"));
        assert_eq!(normalize("OILO-0000-0000").as_deref(), Some("011000000000"));
        assert_eq!(normalize("K7QF-3MZD"), None, "too short");
        assert_eq!(normalize("K7QF-3MZD-PX9U"), None, "U is not in the alphabet");
        assert_eq!(normalize("K7QF-3MZD-PX9é"), None);
    }
}
