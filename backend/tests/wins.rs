//! The wins boards (migrations/0111_wins_boards.sql) against a real Postgres:
//! what counts, the friend cap, early resigns, bots, new accounts, the board's
//! order and win rate, and a player's record.
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
    let app = router(state).layer(MockConnectInfo(SocketAddr::from(([10, 0, 0, 3], 1234))));
    Some((app, pool))
}

async fn call(app: &Router, path: &str, token: &str, body: Value) -> (StatusCode, Value) {
    let req = Request::post(path)
        .header("content-type", "application/json")
        .header("x-flapjaw-api", "1")
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

/// An account old enough with enough checked runs that its losses count.
async fn settled_in(pool: &PgPool, player: &str) {
    sqlx::query("update auth.users set created_at = now() - interval '10 days' where id = $1::uuid")
        .bind(player)
        .execute(pool)
        .await
        .unwrap();
    sqlx::query("insert into public.players (id, name) values ($1::uuid, 'Seasoned') on conflict do nothing")
        .bind(player)
        .execute(pool)
        .await
        .unwrap();
    sqlx::query(
        "insert into public.runs (player_id, score, day, gameplay_version, seed, status, board)
         select $1::uuid, 7, current_date - 5, 1, 1, 'ok', 'endless' from generate_series(1, 20)",
    )
    .bind(player)
    .execute(pool)
    .await
    .unwrap();
}

/// A one-round battle (first to 1) that `ta` wins, invite or random.
async fn quick_battle(app: &Router, pool: &PgPool, ta: &str, tb: &str, a_score: i64, b_score: i64) -> i64 {
    let (battle, code) = new_invite(app, ta, "WinA").await;
    sqlx::query("update public.battles set first_to = 1 where id = $1").bind(battle).execute(pool).await.unwrap();
    play(app, ta, "WinA", battle, 1, a_score, json!([1])).await;
    ok(app, "battle_join", tb, json!({"p_code": code, "p_name": "WinB", "p_flyer": "buzz"})).await;
    check_all(pool, battle).await;
    play(app, tb, "WinB", battle, 1, b_score, json!([2])).await;
    check_all(pool, battle).await;
    battle
}

async fn result(pool: &PgPool, battle: i64) -> (bool, String) {
    sqlx::query_as("select counted, reason from public.match_results where battle = $1")
        .bind(battle)
        .fetch_one(pool)
        .await
        .unwrap()
}

#[tokio::test]
async fn a_played_battle_counts_once_per_friend_a_week() {
    let Some((app, pool)) = setup().await else { return };
    let (_, ta) = player(&app).await;
    let (pb, tb) = player(&app).await;
    let battle = quick_battle(&app, &pool, &ta, &tb, 20, 10).await;
    assert_eq!(result(&pool, battle).await, (false, "new account".into()), "a new account's loss");
    settled_in(&pool, &pb).await;
    let battle = quick_battle(&app, &pool, &ta, &tb, 20, 10).await;
    assert_eq!(result(&pool, battle).await, (true, String::new()));
    let battle = quick_battle(&app, &pool, &ta, &tb, 20, 10).await;
    assert_eq!(result(&pool, battle).await, (false, "friend cap".into()), "one win per friend a week");
    // A loser whose runs average under 5 points: tanking.
    let (pc, tc) = player(&app).await;
    settled_in(&pool, &pc).await;
    let battle = quick_battle(&app, &pool, &ta, &tc, 20, 2).await;
    assert_eq!(result(&pool, battle).await, (false, "loser under 5 points".into()));
}

#[tokio::test]
async fn resigns_closes_and_bots() {
    let Some((app, pool)) = setup().await else { return };
    let (_, ta) = player(&app).await;
    let (pb, tb) = player(&app).await;
    settled_in(&pool, &pb).await;
    // Resigned before round 3: nobody's.
    let (battle, code) = new_invite(&app, &ta, "ResA").await;
    ok(&app, "battle_join", &tb, json!({"p_code": code, "p_name": "ResB", "p_flyer": "buzz"})).await;
    ok(&app, "battle_resign", &tb, json!({"p_battle": battle})).await;
    assert_eq!(result(&pool, battle).await, (false, "resigned early".into()));
    // Closed: no result for either.
    let (battle, code) = new_invite(&app, &ta, "ResA").await;
    play(&app, &ta, "ResA", battle, 1, 5, json!([1])).await;
    ok(&app, "battle_join", &tb, json!({"p_code": code, "p_name": "ResB", "p_flyer": "buzz"})).await;
    sqlx::query("update public.battles set last_move_at = now() - interval '8 days' where id = $1")
        .bind(battle)
        .execute(&pool)
        .await
        .unwrap();
    ok(&app, "battle_close", &ta, json!({"p_battle": battle})).await;
    assert_eq!(result(&pool, battle).await, (false, "closed".into()));
    // Against a bot: never on the boards.
    sqlx::query("update public.players set bot = true where id = $1::uuid").bind(&pb).execute(&pool).await.unwrap();
    let battle = quick_battle(&app, &pool, &ta, &tb, 20, 10).await;
    assert_eq!(result(&pool, battle).await, (false, "bot".into()));
}

#[tokio::test]
async fn the_board_ranks_counted_wins_and_shows_a_record() {
    let Some((app, pool)) = setup().await else { return };
    let (pa, ta) = player(&app).await;
    let mut beaten = vec![];
    // A beats three different players (random-like: each a new friend).
    for _ in 0..3 {
        let (pb, tb) = player(&app).await;
        settled_in(&pool, &pb).await;
        quick_battle(&app, &pool, &ta, &tb, 20, 10).await;
        beaten.push(tb);
    }
    // And loses once.
    let (pd, td) = player(&app).await;
    settled_in(&pool, &pa).await;
    let lost = quick_battle(&app, &pool, &td, &ta, 30, 10).await;
    assert_eq!(result(&pool, lost).await.0, true);
    let board = ok(&app, "get_wins_board", &ta, json!({"p_mode": "battle", "p_period": "week"})).await;
    assert_eq!(board["me"]["wins"], json!(3), "{board}");
    assert_eq!(board["me"]["losses"], json!(1));
    assert_eq!(board["me"]["rate"], json!(75), "rate from 3 matches this week");
    assert!(board["resets_in_s"].as_i64().unwrap() > 0);
    let entries = board["entries"].as_array().unwrap();
    let me = entries.iter().find(|e| e["is_me"] == json!(true)).unwrap();
    let all = ok(&app, "get_wins_board", &ta, json!({"p_mode": "battle", "p_period": "all"})).await;
    assert_eq!(all["me"]["rate"], Value::Null, "all time: no rate below 10 matches");
    let rec =
        ok(&app, "get_match_record", &td, json!({"p_mode": "battle", "p_period": "week", "p_who": me["who"]})).await;
    assert_eq!(rec["wins"], json!(3), "{rec}");
    assert_eq!(rec["best_streak"], json!(3));
    assert_eq!(rec["last"][0]["result"], json!("lost"), "newest first");
    assert_eq!(rec["last"].as_array().unwrap().len(), 4);
    let _ = (pd, beaten);
    let (status, _) = call(&app, "/v1/get_wins_board", &ta, json!({"p_mode": "battle", "p_period": "month"})).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}
