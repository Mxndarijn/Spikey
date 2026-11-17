//! Duel over a real WebSocket against a real Postgres (backend/src/duel_ws.rs):
//! sign-in, an invite and the random queue, the countdown, relayed taps, the
//! clock check, a lost connection and its rejoin, leaving the match and the
//! stored result. The rules themselves are tested in src/duel.rs.
//!
//! Needs DATABASE_URL (tools/backend_test.ps1). Without it every test here
//! says so and passes.

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use flapjaw_server::app::{router, AppState};
use flapjaw_server::config::Config;
use flapjaw_server::db;
use flapjaw_server::limits::Limits;
use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use sqlx::PgPool;
use tokio::net::TcpStream;
use tokio::sync::Notify;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::{connect_async, MaybeTlsStream, WebSocketStream};

type Ws = WebSocketStream<MaybeTlsStream<TcpStream>>;

async fn server() -> Option<(String, PgPool)> {
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
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, router(state).into_make_service_with_connect_info::<SocketAddr>()).await.unwrap();
    });
    Some((format!("127.0.0.1:{}", addr.port()), pool))
}

/// A new player: (id, access token).
async fn player(host: &str) -> (String, String) {
    let key = flapjaw_server::auth::new_token("Fj-");
    let res: Value = reqwest::Client::new()
        .post(format!("http://{host}/v1/auth/anon"))
        .header("x-flapjaw-api", "1")
        .json(&json!({"device_key": key}))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    (res["player_id"].as_str().unwrap().into(), res["access_token"].as_str().unwrap().into())
}

async fn open(host: &str, token: &str, name: &str, version: i64) -> Ws {
    let (mut ws, _) = connect_async(format!("ws://{host}/v1/duel/ws")).await.unwrap();
    send(&mut ws, json!({"t": "hello", "token": token, "version": version, "name": name, "flyer": "buzz"})).await;
    let w = until(&mut ws, "welcome").await;
    assert!(w["player"].is_string(), "{w}");
    ws
}

async fn send(ws: &mut Ws, v: Value) {
    ws.send(Message::Text(v.to_string().into())).await.unwrap();
}

/// The next message of this kind (others are skipped), within 15 s.
async fn until(ws: &mut Ws, kind: &str) -> Value {
    let wait = tokio::time::timeout(Duration::from_secs(15), async {
        while let Some(Ok(msg)) = ws.next().await {
            if let Message::Text(t) = msg {
                let v: Value = serde_json::from_str(&t).unwrap();
                if v["t"] == kind {
                    return v;
                }
            }
        }
        panic!("socket closed before {kind}");
    });
    wait.await.unwrap_or_else(|_| panic!("no {kind} in 15 s"))
}

#[tokio::test]
async fn an_invite_match_relays_taps_and_ends_when_one_leaves() {
    let Some((host, pool)) = server().await else { return };
    let (pa, ta) = player(&host).await;
    let (pb, tb) = player(&host).await;
    let mut a = open(&host, &ta, "DuelAda", 7001).await;
    let mut b = open(&host, &tb, "DuelMira", 7001).await;
    send(&mut a, json!({"t": "invite"})).await;
    let code = until(&mut a, "invite").await["code"].as_str().unwrap().to_string();
    assert_eq!(code.len(), 6);
    send(&mut b, json!({"t": "join", "code": code.to_lowercase()})).await;
    let m = until(&mut a, "matched").await;
    assert_eq!(m["rival"]["name"], json!("DuelMira"), "{m}");
    assert_eq!(m["random"], json!(false));
    let ca = until(&mut a, "countdown").await;
    let cb = until(&mut b, "countdown").await;
    assert_eq!(ca["seed"], cb["seed"], "both fly the same map");
    assert_eq!(ca["round"], json!(1));
    // The countdown, then the round: A says it is at tick 30 with one tap.
    tokio::time::sleep(Duration::from_millis(3700)).await;
    send(&mut a, json!({"t": "ticks", "tick": 30, "taps": [5]})).await;
    let r = until(&mut b, "rival").await;
    assert_eq!((r["tick"].clone(), r["taps"].clone()), (json!(30), json!([5])), "B sees A's taps");
    // Far ahead of the clock: refused.
    send(&mut a, json!({"t": "ticks", "tick": 5000, "taps": []})).await;
    let e = until(&mut a, "error").await;
    assert_eq!(e["message"], json!("ahead of the clock"));
    // A drops and comes back: put back in the round.
    drop(a);
    until(&mut b, "rival_gone").await;
    let mut a = open(&host, &ta, "DuelAda", 7001).await;
    let back = until(&mut a, "resume").await;
    assert_eq!(back["round"], json!(1), "{back}");
    assert_eq!(back["last_tick"], json!(30), "where the server has A");
    until(&mut b, "rival_back").await;
    // B gives up in round 1: A wins, and it is stored, not counted (left early).
    send(&mut b, json!({"t": "leave"})).await;
    let over = until(&mut a, "match_over").await;
    assert_eq!((over["winner"].clone(), over["ended_by"].clone()), (json!("me"), json!("left")), "{over}");
    let over_b = until(&mut b, "match_over").await;
    assert_eq!(over_b["winner"], json!("them"));
    tokio::time::sleep(Duration::from_millis(300)).await;
    let (counted, reason): (bool, String) = sqlx::query_as(
        "select m.counted, m.reason from public.match_results m
         where m.mode = 'duel' and m.player_a = $1::uuid and m.player_b = $2::uuid",
    )
    .bind(&pa)
    .bind(&pb)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!((counted, reason.as_str()), (false, "left early"));
}

#[tokio::test]
async fn the_random_queue_pairs_the_same_version_only() {
    let Some((host, _)) = server().await else { return };
    let (_, ta) = player(&host).await;
    let (_, tb) = player(&host).await;
    let (_, tc) = player(&host).await;
    let mut a = open(&host, &ta, "QueueA", 7101).await;
    let mut c = open(&host, &tc, "QueueC", 7102).await;
    send(&mut a, json!({"t": "queue"})).await;
    until(&mut a, "queued").await;
    send(&mut c, json!({"t": "queue"})).await;
    until(&mut c, "queued").await;
    let mut b = open(&host, &tb, "QueueB", 7101).await;
    send(&mut b, json!({"t": "queue"})).await;
    let m = until(&mut b, "matched").await;
    assert_eq!(m["rival"]["name"], json!("QueueA"), "same version: {m}");
    assert_eq!(m["random"], json!(true));
    until(&mut a, "matched").await;
    send(&mut c, json!({"t": "cancel"})).await;
    send(&mut a, json!({"t": "leave"})).await;
    until(&mut b, "match_over").await;
}

#[tokio::test]
async fn a_bad_token_is_turned_away() {
    let Some((host, _)) = server().await else { return };
    let (mut ws, _) = connect_async(format!("ws://{host}/v1/duel/ws")).await.unwrap();
    send(&mut ws, json!({"t": "hello", "token": "nope", "version": 1})).await;
    let e = until(&mut ws, "error").await;
    assert_eq!(e["message"], json!("session_gone"));
}

#[tokio::test]
async fn an_older_app_is_told_to_update() {
    let Some((host, _)) = server().await else { return };
    let (_, t) = player(&host).await;
    let (mut ws, _) = connect_async(format!("ws://{host}/v1/duel/ws")).await.unwrap();
    let old = sim::sim_config::SimConfig::GAMEPLAY_VERSION - 1;
    send(&mut ws, json!({"t": "hello", "token": t, "version": old, "name": "OldApp"})).await;
    let e = until(&mut ws, "error").await;
    assert_eq!(e["message"], json!("update_required"), "Duel runs only on the newest version");
}
