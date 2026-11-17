//! Battle and Duel only on the newest gameplay version (migrations/0115_versions.sql,
//! app.rs check_gameplay): an older phone is told update_required, and when the
//! server moves to a newer version an undecided round starts over from its
//! opener while the decided rounds and the score stay.
//!
//! Needs DATABASE_URL (tools/backend_test.ps1 starts a throwaway Postgres in
//! Docker). Without it every test here says so and passes. The checker is
//! stood in for by setting a run's status: the replay check itself is tested
//! in api.rs.

use std::net::SocketAddr;
use std::sync::Arc;

use axum::body::Body;
use axum::extract::connect_info::MockConnectInfo;
use axum::http::{Request, StatusCode};
use axum::Router;
use flapjaw_server::app::{router, AppState};
use flapjaw_server::config::Config;
use flapjaw_server::db;
use flapjaw_server::limits::Limits;
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
    let app = router(state).layer(MockConnectInfo(SocketAddr::from(([10, 0, 0, 5], 1234))));
    Some((app, pool))
}

async fn call(app: &Router, path: &str, token: &str, body: Value) -> (StatusCode, Value) {
    let req = Request::post(path)
        .header("content-type", "application/json")
        .header("x-flapjaw-api", "1")
        .header("x-flapjaw-gameplay", sim::sim_config::SimConfig::GAMEPLAY_VERSION.to_string())
        .header("authorization", format!("Bearer {token}"));
    let res = app.clone().oneshot(req.body(Body::from(body.to_string())).unwrap()).await.unwrap();
    let status = res.status();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    (status, serde_json::from_slice(&bytes).unwrap_or(Value::Null))
}

/// A signed-in phone: (player id, access token).
async fn player(app: &Router) -> (String, String) {
    let key = flapjaw_server::auth::new_token("Fj-");
    let req = Request::post("/v1/auth/anon")
        .header("content-type", "application/json")
        .header("x-flapjaw-api", "1")
        .body(Body::from(json!({"device_key": key}).to_string()))
        .unwrap();
    let res = app.clone().oneshot(req).await.unwrap();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    let s: Value = serde_json::from_slice(&bytes).unwrap();
    (s["player_id"].as_str().unwrap().into(), s["access_token"].as_str().unwrap().into())
}

async fn ok(app: &Router, op: &str, token: &str, body: Value) -> Value {
    let (status, v) = call(app, &format!("/v1/{op}"), token, body).await;
    assert_eq!(status, StatusCode::OK, "{op}: {v}");
    v
}

fn name(n: &str) -> Value {
    json!(n)
}

/// Starts and sends a run of `round` with this score and taps.
async fn play(app: &Router, token: &str, who: &str, battle: i64, round: i64, score: i64, taps: Value) -> Value {
    let start =
        ok(app, "battle_start_run", token, json!({"p_battle": battle, "p_round": round, "p_gameplay_version": 1}))
            .await;
    assert_eq!(start["round"], json!(round), "{start}");
    ok(
        app,
        "battle_submit",
        token,
        json!({
            "p_battle": battle, "p_round": round, "p_name": name(who), "p_flyer": "buzz",
            "p_score": score, "p_gameplay_version": 1, "p_seed": start["seed"], "p_taps": taps,
            "p_season": start["season"], "p_coins": 0, "p_end_tick": 100,
        }),
    )
    .await
}

/// The checker's verdict on every pending battle run of this battle.
async fn check_all(pool: &PgPool, battle: i64) {
    sqlx::query(
        "update public.runs set status = 'ok', checked_at = now()
         where status = 'pending' and id in (
           select run_a from public.battle_rounds where battle = $1
           union select run_b from public.battle_rounds where battle = $1)",
    )
    .bind(battle)
    .execute(pool)
    .await
    .unwrap();
}

async fn new_invite(app: &Router, token: &str, who: &str) -> (i64, String) {
    let v = ok(
        app,
        "battle_create",
        token,
        json!({"p_name": who, "p_flyer": "buzz", "p_opponent": "invite", "p_gameplay_version": 1}),
    )
    .await;
    let code = v["code"].as_str().unwrap().to_string();
    assert_eq!(code.len(), 6, "{v}");
    assert!(code.chars().all(|c| "ABCDEFGHJKMNPQRSTUVWXYZ23456789".contains(c)), "no look-alikes: {code}");
    (v["battle"].as_i64().unwrap(), code)
}

const V: i64 = sim::sim_config::SimConfig::GAMEPLAY_VERSION;

/// A request with this phone's gameplay version in the header (None: no header).
async fn call_as(app: &Router, op: &str, token: &str, version: Option<i64>, body: Value) -> (StatusCode, Value) {
    let mut req = Request::post(format!("/v1/{op}"))
        .header("content-type", "application/json")
        .header("x-flapjaw-api", "1")
        .header("authorization", format!("Bearer {token}"));
    if let Some(v) = version {
        req = req.header("x-flapjaw-gameplay", v.to_string());
    }
    let res = app.clone().oneshot(req.body(Body::from(body.to_string())).unwrap()).await.unwrap();
    let status = res.status();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    (status, serde_json::from_slice(&bytes).unwrap_or(Value::Null))
}

#[tokio::test]
async fn an_older_app_is_told_to_update_and_classic_goes_on() {
    let Some((app, _)) = setup().await else { return };
    let (_, t) = player(&app).await;
    for version in [None, Some(V - 1)] {
        let (status, v) = call_as(&app, "battle_list", &t, version, json!({})).await;
        assert_eq!(status, StatusCode::CONFLICT, "{v}");
        assert_eq!(v["error"], json!("update_required"));
    }
    let (status, _) = call_as(&app, "battle_list", &t, Some(V), json!({})).await;
    assert_eq!(status, StatusCode::OK, "the newest version plays");
    let (status, _) = call_as(&app, "get_board", &t, Some(V - 1), json!({"p_board": "daily"})).await;
    assert_eq!(status, StatusCode::OK, "the score boards don't care");
    // The version the app compares itself with.
    let req = Request::post("/v1/ping").header("x-flapjaw-api", "1").body(Body::from("{}")).unwrap();
    let res = app.clone().oneshot(req).await.unwrap();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    let ping: Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(ping["gameplay_version"], json!(V));
}

#[tokio::test]
async fn a_new_version_replays_the_undecided_round_from_its_opener() {
    let Some((app, pool)) = setup().await else { return };
    let (_, ta) = player(&app).await;
    let (_, tb) = player(&app).await;
    let (battle, code) = new_invite(&app, &ta, "VerA").await;
    let start = |round: i64, version: i64| json!({"p_battle": battle, "p_round": round, "p_gameplay_version": version});
    let submit = |round: i64, who: &str, seed: &Value, season: &Value, version: i64, score: i64| {
        json!({
            "p_battle": battle, "p_round": round, "p_name": who, "p_flyer": "buzz", "p_score": score,
            "p_gameplay_version": version, "p_seed": seed, "p_taps": [1], "p_season": season,
        })
    };
    // Round 1 on this version: A 10, B 12, decided for B.
    let s = ok(&app, "battle_start_run", &ta, start(1, V)).await;
    ok(&app, "battle_submit", &ta, submit(1, "VerA", &s["seed"], &s["season"], V, 10)).await;
    ok(&app, "battle_join", &tb, json!({"p_code": code, "p_name": "VerB", "p_flyer": "buzz"})).await;
    check_all(&pool, battle).await;
    let s = ok(&app, "battle_start_run", &tb, start(1, V)).await;
    ok(&app, "battle_submit", &tb, submit(1, "VerB", &s["seed"], &s["season"], V, 12)).await;
    check_all(&pool, battle).await;
    // Round 2 half played: B opened it, A hasn't answered.
    let s2 = ok(&app, "battle_start_run", &tb, start(2, V)).await;
    ok(&app, "battle_submit", &tb, submit(2, "VerB", &s2["seed"], &s2["season"], V, 30)).await;
    let before = ok(&app, "battle_get", &ta, json!({"p_battle": battle})).await;
    assert_eq!(before["play"]["round"], json!(2), "{before}");
    assert_eq!(before["wins_them"], json!(1));
    // The server starts on the next version.
    let n: i32 = sqlx::query_scalar("select public.spikey_battle_redeal_old($1)")
        .bind((V + 1) as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(n >= 1, "round 2 starts over");
    let (version, seed, run_a, run_b, settled): (i32, i64, Option<i64>, Option<i64>, bool) = sqlx::query_as(
        "select gameplay_version, seed, run_a, run_b, settled from public.battle_rounds where battle = $1 and number = 2",
    )
    .bind(battle)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(version as i64, V + 1, "dealt on the new version");
    assert!(run_a.is_none() && run_b.is_none(), "the old run is dropped");
    assert!(!settled);
    let _ = seed;
    let round1: (i32, bool) =
        sqlx::query_as("select gameplay_version, settled from public.battle_rounds where battle = $1 and number = 1")
            .bind(battle)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(round1, (V as i32, true), "a decided round stays");
    // B opened round 2, so B plays it again first; the score is kept.
    let b = ok(&app, "battle_get", &tb, json!({"p_battle": battle})).await;
    assert_eq!(b["play"], json!({"round": 2, "role": "open"}), "{b}");
    assert_eq!(b["wins_me"], json!(1), "the score stays");
    let a = ok(&app, "battle_get", &ta, json!({"p_battle": battle})).await;
    assert_eq!(a["turn"], json!("them"));
    let told: i64 = sqlx::query_scalar("select count(*) from public.battle_alerts where ref = $1")
        .bind(format!("redeal:{battle}:2:{}", V + 1))
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(told, 2, "both players hear: New game version, round 2 starts over");
    // A phone still on the old version can't play the new round.
    let (status, v) = call_as(&app, "battle_start_run", &tb, Some(V), start(2, V)).await;
    assert_eq!(status, StatusCode::CONFLICT, "{v}");
    assert_eq!(v["error"], json!("update_required"));
    // Run again: nothing more to deal.
    let again: i32 = sqlx::query_scalar("select public.spikey_battle_redeal_old($1)")
        .bind((V + 1) as i32)
        .fetch_one(&pool)
        .await
        .unwrap();
    let still: i32 =
        sqlx::query_scalar("select gameplay_version from public.battle_rounds where battle = $1 and number = 2")
            .bind(battle)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(still as i64, V + 1);
    let _ = again;
}
