//! The game's operations: `POST /v1/<op>` with the same name, arguments and
//! answer as the SQL function of that name (backend/migrations/). Each
//! call runs the SQL function as the signed-in player: the server sets
//! `request.jwt.claim.sub` for the transaction, which is what `auth.uid()`
//! reads (the functions were written for Supabase, which did the same).
//!
//! The body is passed to Postgres as one jsonb value and each argument is
//! taken out of it with its type, by name (`f(p_board => ($1->>'p_board')::text)`),
//! so arguments the body leaves out keep their SQL defaults. An argument the
//! function doesn't take is a 404, like PostgREST's, which the game's queue
//! reads as "send it without the newest arguments".

use serde_json::{Map, Value};
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::{ApiError, ApiResult};

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Arg {
    Text,
    Int,
    BigInt,
    Json,
    Time,
    Bool,
    Uuid,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Ret {
    Json,
    Void,
    Text,
    Int,
}

pub struct Op {
    pub name: &'static str,
    pub args: &'static [(&'static str, Arg)],
    pub ret: Ret,
    /// A new run to check: start a checker round now.
    pub new_run: bool,
}

use Arg::*;

/// Every operation the game calls, with its SQL signature.
pub const OPS: &[Op] = &[
    Op { name: "ping", args: &[], ret: Ret::Int, new_run: false },
    Op { name: "set_player", args: &[("p_name", Text), ("p_flyer", Text)], ret: Ret::Void, new_run: false },
    Op { name: "get_board", args: &[("p_board", Text)], ret: Ret::Json, new_run: false },
    Op { name: "get_run", args: &[("p_run", BigInt)], ret: Ret::Json, new_run: false },
    Op {
        name: "submit_run",
        args: &[
            ("p_name", Text),
            ("p_flyer", Text),
            ("p_score", Int),
            ("p_gameplay_version", Int),
            ("p_seed", BigInt),
            ("p_taps", Json),
            ("p_played_at", Time),
            ("p_loadout", Json),
            ("p_season", Int),
            ("p_coins", Int),
            ("p_end_tick", Int),
            ("p_revives", Json),
        ],
        ret: Ret::Void,
        new_run: true,
    },
    Op {
        name: "submit_daily_run",
        args: &[
            ("p_try", Uuid),
            ("p_name", Text),
            ("p_flyer", Text),
            ("p_score", Int),
            ("p_gameplay_version", Int),
            ("p_seed", BigInt),
            ("p_taps", Json),
            ("p_loadout", Json),
            ("p_season", Int),
            ("p_coins", Int),
            ("p_end_tick", Int),
        ],
        ret: Ret::Void,
        new_run: true,
    },
    Op { name: "get_daily_run", args: &[], ret: Ret::Json, new_run: false },
    Op { name: "start_daily_try", args: &[("p_name", Text), ("p_flyer", Text)], ret: Ret::Json, new_run: false },
    Op { name: "get_wallet", args: &[], ret: Ret::Json, new_run: false },
    Op { name: "claim_prizes", args: &[], ret: Ret::Json, new_run: false },
    Op {
        name: "spend_diamonds",
        args: &[("p_amount", Int), ("p_reason", Text), ("p_ref", Text), ("p_request", Uuid)],
        ret: Ret::Json,
        new_run: false,
    },
    Op { name: "get_earn_status", args: &[], ret: Ret::Json, new_run: false },
    Op { name: "sync_profile", args: &[("p_data", Json), ("p_base", BigInt)], ret: Ret::Json, new_run: false },
    Op {
        name: "register_push",
        args: &[("p_token", Text), ("p_platform", Text), ("p_utc_offset_min", Int)],
        ret: Ret::Void,
        new_run: false,
    },
    Op { name: "set_push_enabled", args: &[("p_enabled", Bool)], ret: Ret::Void, new_run: false },
    Op { name: "send_test_push", args: &[], ret: Ret::Text, new_run: false },
    Op { name: "get_my_runs", args: &[("p_limit", Int)], ret: Ret::Json, new_run: false },
];

pub fn find(name: &str) -> Option<&'static Op> {
    OPS.iter().find(|op| op.name == name)
}

fn cast(kind: Arg, name: &str) -> String {
    match kind {
        Text => format!("($1->>'{name}')"),
        Int => format!("($1->>'{name}')::integer"),
        BigInt => format!("($1->>'{name}')::bigint"),
        Json => format!("($1->'{name}')"),
        Time => format!("($1->>'{name}')::timestamptz"),
        Bool => format!("($1->>'{name}')::boolean"),
        Uuid => format!("($1->>'{name}')::uuid"),
    }
}

/// The SQL for one call with the arguments this body has, or 404 for one the
/// function doesn't take. Names come only from `OPS`, never from the request.
pub fn statement(op: &Op, body: &Map<String, Value>) -> ApiResult<String> {
    for key in body.keys() {
        if !op.args.iter().any(|(a, _)| a == key) {
            return Err(ApiError::not_found(format!("{} takes no argument {key}", op.name)));
        }
    }
    let args: Vec<String> = op
        .args
        .iter()
        .filter(|(a, _)| body.get(*a).is_some_and(|v| !v.is_null()))
        .map(|(a, kind)| format!("{a} => {}", cast(*kind, a)))
        .collect();
    let call = format!("public.{}({})", op.name, args.join(", "));
    Ok(match op.ret {
        Ret::Json => format!("select coalesce({call}, 'null'::jsonb)"),
        Ret::Void => format!("select 'null'::jsonb from (select {call}) as done"),
        Ret::Text | Ret::Int => format!("select to_jsonb({call})"),
    })
}

/// Runs one operation as `player` and gives its answer.
pub async fn call(pool: &PgPool, player: Uuid, op: &Op, body: &Value) -> ApiResult<Value> {
    let empty = Map::new();
    let map = match body {
        Value::Object(m) => m,
        Value::Null => &empty,
        _ => return Err(ApiError::bad("the body must be a JSON object")),
    };
    let sql = statement(op, map)?;
    let mut tx = pool.begin().await?;
    sqlx::query("select set_config('request.jwt.claim.sub', $1, true)")
        .bind(player.to_string())
        .execute(&mut *tx)
        .await?;
    let answer: Value = sqlx::query_scalar(&sql).bind(Value::Object(map.clone())).fetch_one(&mut *tx).await?;
    tx.commit().await?;
    Ok(answer)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn body(v: Value) -> Map<String, Value> {
        v.as_object().unwrap().clone()
    }

    #[test]
    fn only_the_arguments_sent_are_passed() {
        let op = find("submit_run").unwrap();
        let sql = statement(op, &body(json!({"p_name": "bee", "p_score": 3, "p_taps": [1]}))).unwrap();
        assert_eq!(
            sql,
            "select 'null'::jsonb from (select public.submit_run(p_name => ($1->>'p_name'), \
             p_score => ($1->>'p_score')::integer, p_taps => ($1->'p_taps'))) as done"
        );
    }

    #[test]
    fn an_unknown_argument_is_a_404() {
        let op = find("get_board").unwrap();
        let err = statement(op, &body(json!({"p_board": "daily", "p_x": 1}))).unwrap_err();
        assert_eq!(err.status, axum::http::StatusCode::NOT_FOUND);
    }

    #[test]
    fn answers_are_always_json() {
        let sql = statement(find("send_test_push").unwrap(), &Map::new()).unwrap();
        assert_eq!(sql, "select to_jsonb(public.send_test_push())");
        let sql = statement(find("get_wallet").unwrap(), &Map::new()).unwrap();
        assert_eq!(sql, "select coalesce(public.get_wallet(), 'null'::jsonb)");
    }

    #[test]
    fn every_client_call_is_an_operation() {
        // What services/*.gd calls through call_db.
        for name in [
            "get_board",
            "get_run",
            "set_player",
            "submit_run",
            "submit_daily_run",
            "get_daily_run",
            "start_daily_try",
            "get_wallet",
            "claim_prizes",
            "spend_diamonds",
            "get_earn_status",
            "sync_profile",
            "register_push",
            "set_push_enabled",
            "send_test_push",
            "get_my_runs",
        ] {
            assert!(find(name).is_some(), "{name}");
        }
    }
}
