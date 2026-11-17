//! Sends the queued board alerts (lost prize spots) through Firebase Cloud
//! Messaging. A port of the old Edge Function send-alerts: the database decides
//! who gets an alert and what it says; this only carries the outbox to
//! Firebase and reports back. Off when FIREBASE_SERVICE_ACCOUNT is empty.

use base64::Engine;
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::PgPool;

const SCOPE: &str = "https://www.googleapis.com/auth/firebase.messaging";
/// The Android notification channel the game creates for these.
pub const CHANNEL: &str = "board_alerts";
/// Battle alerts (your turn, nudges, results) have their own channel, so a
/// player can mute battles and keep board alerts.
pub const BATTLE_CHANNEL: &str = "battles";
const BATCH: i32 = 100;

#[derive(Deserialize, Clone)]
pub struct Account {
    pub project_id: String,
    pub client_email: String,
    pub private_key: String,
    pub token_uri: String,
}

/// The service account key: the JSON text itself, or that text in base64.
pub fn parse_account(text: &str) -> Option<Account> {
    let t = text.trim();
    if t.is_empty() {
        return None;
    }
    let json = if t.starts_with('{') {
        t.to_string()
    } else {
        String::from_utf8(base64::engine::general_purpose::STANDARD.decode(t).ok()?).ok()?
    };
    serde_json::from_str(&json).ok()
}

/// What Firebase is asked to deliver for one alert.
pub fn message(alert: &Value) -> Value {
    let battle = alert["line"] == "battle";
    let channel = if battle { BATTLE_CHANNEL } else { CHANNEL };
    let kind = if battle { "battle_alert" } else { "board_alert" };
    // Data values are strings in FCM. A tapped battle alert opens its battle.
    let mut data = json!({"kind": kind});
    if let Some(id) = alert["battle"].as_str().filter(|s| !s.is_empty()) {
        data["battle"] = json!(id);
    }
    json!({
        "message": {
            "token": alert["token"],
            "notification": {"title": alert["title"], "body": alert["body"]},
            "data": data,
            "android": {"priority": "HIGH", "notification": {"channel_id": channel}},
            "apns": {"payload": {"aps": {"sound": "default"}}},
        }
    })
}

/// Why Firebase refused a message, for the log: the HTTP status, Firebase's
/// status and its FCM error code, never the token. THIRD_PARTY_AUTH_ERROR on an
/// iOS phone means the Firebase project has no APNs key (docs/PUSH_SETUP.md).
pub fn failure_reason(status: u16, body: &Value) -> String {
    let mut out = status.to_string();
    if let Some(s) = body["error"]["status"].as_str() {
        out += &format!(" {s}");
    }
    if let Some(details) = body["error"]["details"].as_array() {
        for code in details.iter().filter_map(|d| d["errorCode"].as_str()) {
            out += &format!(" {code}");
        }
    }
    out
}

/// True when Firebase says this phone's token is gone for good.
pub fn token_is_dead(status: u16, body: &Value) -> bool {
    status == 404
        || body["error"]["details"].as_array().is_some_and(|d| d.iter().any(|x| x["errorCode"] == "UNREGISTERED"))
}

async fn access_token(http: &reqwest::Client, account: &Account) -> Result<String, String> {
    #[derive(serde::Serialize)]
    struct Claims<'a> {
        iss: &'a str,
        scope: &'a str,
        aud: &'a str,
        iat: i64,
        exp: i64,
    }
    let now = chrono::Utc::now().timestamp();
    let claims = Claims { iss: &account.client_email, scope: SCOPE, aud: &account.token_uri, iat: now, exp: now + 600 };
    let key = jsonwebtoken::EncodingKey::from_rsa_pem(account.private_key.as_bytes()).map_err(|e| e.to_string())?;
    let assertion = jsonwebtoken::encode(&jsonwebtoken::Header::new(jsonwebtoken::Algorithm::RS256), &claims, &key)
        .map_err(|e| e.to_string())?;
    let res = http
        .post(&account.token_uri)
        .form(&[("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"), ("assertion", &assertion)])
        .send()
        .await
        .map_err(|e| e.to_string())?;
    let data: Value = res.json().await.map_err(|e| e.to_string())?;
    data["access_token"].as_str().map(str::to_string).ok_or_else(|| "Google sent no access token".into())
}

/// While Battle is paused its alerts are never sent (marked failed, so they don't wait).
pub fn held(alert: &Value, battle_paused: bool) -> bool {
    battle_paused && alert["line"] == "battle"
}

/// One sender round: (sent, failed).
pub async fn round(
    pool: &PgPool,
    http: &reqwest::Client,
    account: &Account,
    battle_paused: bool,
) -> Result<(usize, usize), String> {
    let pending: Value = sqlx::query_scalar("select public.worker_pending_alerts($1)")
        .bind(BATCH)
        .fetch_one(pool)
        .await
        .map_err(|e| e.to_string())?;
    let all = pending.as_array().cloned().unwrap_or_default();
    let mut results = vec![];
    let mut alerts = vec![];
    for alert in all {
        if held(&alert, battle_paused) {
            results.push(json!({"id": alert["id"], "status": "failed"}));
        } else {
            alerts.push(alert);
        }
    }
    if alerts.is_empty() {
        if !results.is_empty() {
            mark(pool, results).await?;
        }
        return Ok((0, 0));
    }
    let token = access_token(http, account).await?;
    let url = format!("https://fcm.googleapis.com/v1/projects/{}/messages:send", account.project_id);
    let (mut sent, mut failed) = (0, 0);
    for alert in &alerts {
        let res = http.post(&url).bearer_auth(&token).json(&message(alert)).send().await;
        match res {
            Ok(r) if r.status().is_success() => {
                sent += 1;
                results.push(json!({"id": alert["id"], "status": "sent"}));
            }
            Ok(r) => {
                failed += 1;
                let status = r.status().as_u16();
                let body: Value = r.json().await.unwrap_or(Value::Null);
                tracing::warn!(
                    "alert {} ({}) not sent: {}",
                    alert["id"],
                    alert["platform"].as_str().unwrap_or("?"),
                    failure_reason(status, &body)
                );
                results
                    .push(json!({"id": alert["id"], "status": "failed", "forget_token": token_is_dead(status, &body)}));
            }
            Err(e) => {
                tracing::warn!("alert {} not sent: {e}", alert["id"]);
                failed += 1;
                results.push(json!({"id": alert["id"], "status": "failed"}));
            }
        }
    }
    mark(pool, results).await?;
    Ok((sent, failed))
}

async fn mark(pool: &PgPool, results: Vec<Value>) -> Result<(), String> {
    sqlx::query("select public.worker_mark_alerts($1)")
        .bind(Value::Array(results))
        .execute(pool)
        .await
        .map_err(|e| e.to_string())?;
    Ok(())
}

/// send_test_push queues only when the database knows a sender
/// (worker_settings push_url and push_secret). The server is the sender now.
pub async fn register_sender(pool: &PgPool) -> Result<(), sqlx::Error> {
    sqlx::query(
        "insert into public.worker_settings (key, value) values
           ('push_url', 'internal://flapjaw-server'), ('push_secret', 'internal')
         on conflict (key) do update set value = excluded.value",
    )
    .execute(pool)
    .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_account_may_come_as_base64() {
        let raw = r#"{"project_id":"p","client_email":"e","private_key":"k","token_uri":"https://t"}"#;
        assert_eq!(parse_account(raw).unwrap().project_id, "p");
        let b64 = base64::engine::general_purpose::STANDARD.encode(raw);
        assert_eq!(parse_account(&b64).unwrap().client_email, "e");
        assert!(parse_account("").is_none());
        assert!(parse_account("not json").is_none());
    }

    #[test]
    fn dead_tokens_are_forgotten() {
        assert!(token_is_dead(404, &Value::Null));
        assert!(token_is_dead(400, &json!({"error": {"details": [{"errorCode": "UNREGISTERED"}]}})));
        assert!(!token_is_dead(500, &json!({})));
    }

    #[test]
    fn failures_say_why_without_the_token() {
        let body = json!({"error": {"status": "INVALID_ARGUMENT",
            "details": [{"@type": "x", "errorCode": "THIRD_PARTY_AUTH_ERROR"}]}});
        assert_eq!(failure_reason(401, &body), "401 INVALID_ARGUMENT THIRD_PARTY_AUTH_ERROR");
        assert_eq!(failure_reason(500, &Value::Null), "500");
    }

    #[test]
    fn battle_alerts_wait_out_the_pause() {
        let battle = json!({"id": -3, "line": "battle"});
        let board = json!({"id": 4, "line": "board"});
        assert!(held(&battle, true));
        assert!(!held(&battle, false));
        assert!(!held(&board, true));
    }

    #[test]
    fn messages_use_the_games_channel() {
        let m = message(&json!({"token": "t", "title": "Lost #3", "body": "x"}));
        assert_eq!(m["message"]["android"]["notification"]["channel_id"], CHANNEL);
        assert_eq!(m["message"]["token"], "t");
        let b = message(&json!({"token": "t", "title": "Your turn!", "body": "x", "line": "battle"}));
        assert_eq!(b["message"]["android"]["notification"]["channel_id"], BATTLE_CHANNEL);
        assert_eq!(b["message"]["data"]["kind"], "battle_alert");
        let t = message(&json!({"token": "t", "title": "Your turn!", "body": "x", "line": "battle", "battle": "12"}));
        assert_eq!(t["message"]["data"]["battle"], "12", "the tap opens battle 12");
    }
}
