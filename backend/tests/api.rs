//! The server against a real Postgres: sign-in, the game's operations, the
//! replay check and phone transfers, through the HTTP routes.
//!
//! Needs DATABASE_URL (a throwaway database: tools/backend_test.ps1 starts
//! one in Docker). Without it every test here says so and passes.

use std::net::SocketAddr;
use std::sync::Arc;

use axum::body::Body;
use axum::extract::connect_info::MockConnectInfo;
use axum::http::{Request, StatusCode};
use axum::Router;
use flapjaw_server::app::{router, AppState};
use flapjaw_server::config::Config;
use flapjaw_server::limits::Limits;
use flapjaw_server::{db, verify};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tokio::sync::Notify;
use tower::ServiceExt;

async fn setup() -> Option<(Router, PgPool)> {
    let Ok(url) = std::env::var("DATABASE_URL") else {
        eprintln!("DATABASE_URL not set: skipped (tools/backend_test.ps1 runs these)");
        return None;
    };
    let pool = db::connect(&url).await.expect("database");
    db::migrate(&pool).await.expect("migrations");
    let state = Arc::new(AppState {
        pool: pool.clone(),
        config: Config::for_tests(&url),
        limits: Limits::new(),
        new_run: Arc::new(Notify::new()),
    });
    let app = router(state).layer(MockConnectInfo(SocketAddr::from(([10, 0, 0, 1], 1234))));
    Some((app, pool))
}

/// One request: (status, answer).
async fn call(app: &Router, path: &str, token: Option<&str>, body: Value) -> (StatusCode, Value) {
    let mut req = Request::post(path).header("content-type", "application/json").header("x-flapjaw-api", "1");
    if let Some(t) = token {
        req = req.header("authorization", format!("Bearer {t}"));
    }
    let res = app.clone().oneshot(req.body(Body::from(body.to_string())).unwrap()).await.unwrap();
    let status = res.status();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    (status, serde_json::from_slice(&bytes).unwrap_or(Value::Null))
}

fn key() -> String {
    flapjaw_server::auth::new_token("Fj-")
}

struct Phone {
    key: String,
    player: String,
    access: String,
    refresh: String,
}

async fn sign_up(app: &Router) -> Phone {
    let key = key();
    let (status, s) = call(app, "/v1/auth/anon", None, json!({"device_key": key})).await;
    assert_eq!(status, StatusCode::OK, "{s}");
    Phone {
        key,
        player: s["player_id"].as_str().unwrap().into(),
        access: s["access_token"].as_str().unwrap().into(),
        refresh: s["refresh_token"].as_str().unwrap().into(),
    }
}

fn golden(name: &str) -> Value {
    let path = format!("{}/../tests/replay/golden/{name}", env!("CARGO_MANIFEST_DIR"));
    serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
}

fn run_body(g: &Value, name: &str) -> Value {
    json!({
        "p_name": name, "p_flyer": "buzz", "p_score": g["score"], "p_gameplay_version": g["gameplay_version"],
        "p_seed": g["seed"], "p_taps": g["taps"], "p_season": g["season"], "p_coins": g["coins"],
        "p_end_tick": g["end_tick"], "p_loadout": {"flyer": "buzz"},
    })
}

#[test]
fn the_migration_list_matches_the_folder() {
    let dir = format!("{}/../supabase/migrations", env!("CARGO_MANIFEST_DIR"));
    let mut files: Vec<String> = std::fs::read_dir(dir)
        .unwrap()
        .map(|e| e.unwrap().file_name().into_string().unwrap())
        .filter(|n| n.ends_with(".sql"))
        .collect();
    files.sort();
    let listed: Vec<&str> = db::MIGRATIONS.iter().map(|m| m.name).filter(|n| n.starts_with("2026")).collect();
    assert_eq!(listed, files, "add the new Supabase migration to db::MIGRATIONS too");
}

#[tokio::test]
async fn migrations_run_once() {
    let Some((_, pool)) = setup().await else { return };
    assert!(db::migrate(&pool).await.unwrap().is_empty(), "nothing left the second time");
}

#[tokio::test]
async fn sign_up_refresh_and_device_key() {
    let Some((app, _)) = setup().await else { return };
    let phone = sign_up(&app).await;
    // The answer got lost and the phone sends the same key: the same player.
    let (_, again) = call(&app, "/v1/auth/anon", None, json!({"device_key": phone.key})).await;
    assert_eq!(again["player_id"], phone.player.as_str());
    // Refresh: a new pair; the old refresh token is spent.
    let (status, s) = call(&app, "/v1/auth/refresh", None, json!({"refresh_token": phone.refresh})).await;
    assert_eq!(status, StatusCode::OK);
    assert_ne!(s["refresh_token"], phone.refresh.as_str());
    let (status, e) = call(&app, "/v1/auth/refresh", None, json!({"refresh_token": phone.refresh})).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(e["error"], "session_gone");
    // The device key signs in as the same player (a restored backup).
    let body = json!({"player_id": phone.player, "device_key": phone.key});
    let (status, s) = call(&app, "/v1/auth/device", None, body).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(s["player_id"], phone.player.as_str());
    let body = json!({"player_id": phone.player, "device_key": key()});
    let (status, e) = call(&app, "/v1/auth/device", None, body).await;
    assert_eq!((status, e["error"].as_str()), (StatusCode::UNAUTHORIZED, Some("unknown_key")));
    let (status, _) = call(&app, "/v1/auth/anon", None, json!({"device_key": "short"})).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn old_apps_and_strangers_are_turned_away() {
    let Some((app, _)) = setup().await else { return };
    let req = Request::post("/v1/get_board")
        .header("content-type", "application/json")
        .body(Body::from(r#"{"p_board":"daily"}"#))
        .unwrap();
    let res = app.clone().oneshot(req).await.unwrap();
    assert_eq!(res.status(), StatusCode::UPGRADE_REQUIRED, "no X-Flapjaw-Api: too old");
    let (status, e) = call(&app, "/v1/get_board", None, json!({"p_board": "daily"})).await;
    assert_eq!((status, e["error"].as_str()), (StatusCode::UNAUTHORIZED, Some("session_gone")));
    let (status, e) = call(&app, "/v1/get_board", Some("fa_nonsense"), json!({})).await;
    assert_eq!((status, e["error"].as_str()), (StatusCode::UNAUTHORIZED, Some("session_gone")));
}

#[tokio::test]
async fn operations_answer_like_supabase() {
    let Some((app, _)) = setup().await else { return };
    let p = sign_up(&app).await;
    let t = Some(p.access.as_str());
    let (status, _) = call(&app, "/v1/set_player", t, json!({"p_name": "apitester", "p_flyer": "buzz"})).await;
    assert_eq!(status, StatusCode::OK);
    let (status, board) = call(&app, "/v1/get_board", t, json!({"p_board": "alltime"})).await;
    assert_eq!(status, StatusCode::OK, "{board}");
    assert!(board["entries"].is_array());
    let (status, _) = call(&app, "/v1/get_board", t, json!({"p_board": "daily", "p_newer": 1})).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "an argument the function doesn't take, like PostgREST");
    let (status, e) = call(&app, "/v1/get_board", t, json!({"p_board": "weekly"})).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "raise exception: refused, dropped from the queue");
    assert_eq!(e["error"], "refused");
    let (status, _) = call(&app, "/v1/no_such_op", t, json!({})).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, w) = call(&app, "/v1/get_wallet", t, json!({})).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(w["diamonds"], 0);
    let save = json!({"p_data": {"coins": 40, "owned": {"flyer": ["buzz", "dash"]}}, "p_base": 0});
    let (status, s) = call(&app, "/v1/sync_profile", t, save).await;
    assert_eq!(status, StatusCode::OK, "{s}");
    assert_eq!(s["status"], "saved");
    let (_, text) = call(&app, "/v1/send_test_push", t, json!({})).await;
    assert!(text.is_string(), "a text answer is a JSON string: {text}");
}

#[tokio::test]
async fn daily_run_tries_run_out() {
    let Some((app, _)) = setup().await else { return };
    let p = sign_up(&app).await;
    let t = Some(p.access.as_str());
    let (status, info) = call(&app, "/v1/get_daily_run", t, json!({})).await;
    assert_eq!(status, StatusCode::OK, "{info}");
    assert!(info.get("seed").is_none(), "the seed only comes with a try");
    for i in 0..3 {
        let (status, tr) = call(&app, "/v1/start_daily_try", t, json!({"p_name": "dailyapi", "p_flyer": "buzz"})).await;
        assert_eq!(status, StatusCode::OK, "try {i}: {tr}");
        assert!(tr.get("seed").is_some());
    }
    let (status, e) = call(&app, "/v1/start_daily_try", t, json!({"p_name": "dailyapi", "p_flyer": "buzz"})).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(e["message"], "no tries left");
}

#[tokio::test]
async fn runs_are_checked_and_shown() {
    let Some((app, pool)) = setup().await else { return };
    let p = sign_up(&app).await;
    let t = Some(p.access.as_str());
    let g = golden("g24_seed_2024.json");
    let (status, e) = call(&app, "/v1/submit_run", t, run_body(&g, "checkme")).await;
    assert_eq!(status, StatusCode::OK, "{e}");
    let mut fake = run_body(&g, "checkme");
    fake["p_score"] = json!(g["score"].as_i64().unwrap() + 50);
    call(&app, "/v1/submit_run", t, fake).await;
    verify::round(&pool).await.unwrap();
    let rows: Vec<(i32, String)> =
        sqlx::query_as("select score, status from public.runs where player_id = $1::uuid order by id")
            .bind(&p.player)
            .fetch_all(&pool)
            .await
            .unwrap();
    let today = chrono::Utc::now().format("%Y-%m-%d").to_string();
    let none_in_play = verify::seasons_around(&today).contains(&-1);
    if none_in_play {
        assert_eq!(rows[0].1, "ok", "the honest run");
    }
    assert_eq!(rows[1].1, "pending", "the Rust check never rejects on its own");
    let queued: i64 = sqlx::query_scalar(
        "select count(*) from backend.godot_queue q join public.runs r on r.id = q.run_id where r.player_id = $1::uuid",
    )
    .bind(&p.player)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(queued >= 1, "headless Godot gets the last word");
    // Godot's verdict goes through the queue.
    let pending: Value = sqlx::query_scalar("select backend.godot_pending_runs(1000)").fetch_one(&pool).await.unwrap();
    let ids: Vec<i64> = pending.as_array().unwrap().iter().map(|r| r["id"].as_i64().unwrap()).collect();
    let results: Vec<Value> = ids.iter().map(|id| json!({"id": id, "status": "rejected", "reason": "godot"})).collect();
    sqlx::query("select backend.godot_record_results($1)").bind(Value::Array(results)).execute(&pool).await.unwrap();
    let left: i64 = sqlx::query_scalar("select count(*) from backend.godot_queue").fetch_one(&pool).await.unwrap();
    assert_eq!(left, 0);
    let (_, mine) = call(&app, "/v1/get_my_runs", t, json!({})).await;
    let runs = mine["runs"].as_array().unwrap();
    assert_eq!(runs.len(), if none_in_play { 1 } else { 0 }, "rejected runs are left out: {mine}");
}

#[tokio::test]
async fn a_transfer_moves_the_player_and_signs_the_old_phone_out() {
    let Some((app, _)) = setup().await else { return };
    let old = sign_up(&app).await;
    let new = sign_up(&app).await;
    let to = Some(old.access.as_str());
    let tn = Some(new.access.as_str());
    call(&app, "/v1/set_player", to, json!({"p_name": "movingbee", "p_flyer": "buzz"})).await;
    call(&app, "/v1/sync_profile", to, json!({"p_data": {"coins": 2310}, "p_base": 0})).await;
    let (status, c) = call(&app, "/v1/transfer/create", to, json!({})).await;
    assert_eq!(status, StatusCode::OK, "{c}");
    let code = c["code"].as_str().unwrap().to_string();
    assert_eq!(code.len(), 12);
    let typed = format!("{}-{}-{}", &code[..4], &code[4..8], &code[8..]).to_lowercase();
    let (status, preview) = call(&app, "/v1/transfer/preview", tn, json!({"code": typed})).await;
    assert_eq!(status, StatusCode::OK, "{preview}");
    assert_eq!(preview["name"], "movingbee");
    assert_eq!(preview["gold"], 2310);
    assert_eq!(preview["this_phone"]["gold"], 0);
    let (status, own) = call(&app, "/v1/transfer/preview", to, json!({"code": code})).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "the old phone can't take its own code: {own}");
    let new_key = key();
    let (status, s) = call(&app, "/v1/transfer/redeem", tn, json!({"code": code, "device_key": new_key})).await;
    assert_eq!(status, StatusCode::OK, "{s}");
    assert_eq!(s["player_id"], old.player.as_str(), "the new phone is that player now");
    // The old phone: every way in says the player moved.
    let (status, e) = call(&app, "/v1/get_wallet", to, json!({})).await;
    assert_eq!((status, e["error"].as_str()), (StatusCode::UNAUTHORIZED, Some("account_moved")));
    let (_, e) = call(&app, "/v1/auth/refresh", None, json!({"refresh_token": old.refresh})).await;
    assert_eq!(e["error"], "account_moved");
    let (_, e) = call(&app, "/v1/auth/device", None, json!({"player_id": old.player, "device_key": old.key})).await;
    assert_eq!(e["error"], "account_moved");
    // The new phone signs in with its new key as the moved player.
    let body = json!({"player_id": old.player, "device_key": new_key});
    let (status, s2) = call(&app, "/v1/auth/device", None, body).await;
    assert_eq!((status, s2["player_id"].as_str()), (StatusCode::OK, Some(old.player.as_str())));
    let moved = s["access_token"].as_str().unwrap();
    let (status, w) = call(&app, "/v1/get_wallet", Some(moved), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{w}");
    // A code works once.
    let other = sign_up(&app).await;
    let (status, e) =
        call(&app, "/v1/transfer/redeem", Some(&other.access), json!({"code": code, "device_key": key()})).await;
    assert_eq!((status, e["error"].as_str()), (StatusCode::GONE, Some("code_used")));
}

#[tokio::test]
async fn code_guessing_runs_into_the_limit() {
    let Some((app, _)) = setup().await else { return };
    let p = sign_up(&app).await;
    let t = Some(p.access.as_str());
    for _ in 0..5 {
        let (status, _) = call(&app, "/v1/transfer/preview", t, json!({"code": "AAAA-BBBB-CCCC"})).await;
        assert_eq!(status, StatusCode::NOT_FOUND);
    }
    let (status, _) = call(&app, "/v1/transfer/preview", t, json!({"code": "AAAA-BBBB-CCCC"})).await;
    assert_eq!(status, StatusCode::TOO_MANY_REQUESTS, "5 tries an hour");
}

#[tokio::test]
async fn codes_per_day_and_cancel() {
    let Some((app, _)) = setup().await else { return };
    let p = sign_up(&app).await;
    let t = Some(p.access.as_str());
    let (_, first) = call(&app, "/v1/transfer/create", t, json!({})).await;
    let (_, _second) = call(&app, "/v1/transfer/create", t, json!({})).await;
    let other = sign_up(&app).await;
    let (status, e) = call(&app, "/v1/transfer/preview", Some(&other.access), json!({"code": first["code"]})).await;
    assert_eq!((status, e["error"].as_str()), (StatusCode::GONE, Some("code_expired")), "a new code cancels the old");
    for _ in 0..3 {
        call(&app, "/v1/transfer/create", t, json!({})).await;
    }
    let (status, _) = call(&app, "/v1/transfer/create", t, json!({})).await;
    assert_eq!(status, StatusCode::TOO_MANY_REQUESTS, "5 codes a day");
    let (status, c) = call(&app, "/v1/transfer/cancel", t, json!({})).await;
    assert_eq!((status, c["cancelled"].as_u64()), (StatusCode::OK, Some(1)));
}
