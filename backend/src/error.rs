//! Error answers: `{"error": "<code>", "message": "..."}` with the status the
//! game's client reads (docs/SERVER_MIGRATION.md, the queued-runs contract):
//! 400 bad data (dropped from the queue), 401 sign in again (or
//! `account_moved`), 404 unknown operation, 426 update the app, 429 slow
//! down, 5xx try later.

use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde_json::json;

#[derive(Debug)]
pub struct ApiError {
    pub status: StatusCode,
    pub code: &'static str,
    pub message: String,
}

impl ApiError {
    pub fn new(status: StatusCode, code: &'static str, message: impl Into<String>) -> ApiError {
        ApiError { status, code, message: message.into() }
    }
    pub fn bad(message: impl Into<String>) -> ApiError {
        ApiError::new(StatusCode::BAD_REQUEST, "bad_request", message)
    }
    pub fn unauthorized(code: &'static str) -> ApiError {
        ApiError::new(StatusCode::UNAUTHORIZED, code, code.replace('_', " "))
    }
    pub fn not_found(message: impl Into<String>) -> ApiError {
        ApiError::new(StatusCode::NOT_FOUND, "not_found", message)
    }
    pub fn too_many() -> ApiError {
        ApiError::new(StatusCode::TOO_MANY_REQUESTS, "rate_limited", "too many tries, wait a while")
    }
    pub fn internal() -> ApiError {
        ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "internal", "the server failed")
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        (self.status, Json(json!({"error": self.code, "message": self.message}))).into_response()
    }
}

impl From<sqlx::Error> for ApiError {
    fn from(e: sqlx::Error) -> ApiError {
        if let sqlx::Error::Database(db) = &e {
            let code = db.code().map(|c| c.to_string()).unwrap_or_default();
            // raise exception in the game's functions ('no tries left', 'invalid taps').
            if code == "P0001" {
                if db.message() == UPDATE_REQUIRED {
                    return update_required();
                }
                return ApiError::new(StatusCode::BAD_REQUEST, "refused", db.message());
            }
            // Bad input: a wrong type, a value out of range, a broken constraint.
            if code.starts_with("22") || code.starts_with("23") {
                return ApiError::bad(db.message());
            }
            // An argument the function doesn't take, like PostgREST's 404.
            if code == "42883" {
                return ApiError::not_found("no such operation or argument");
            }
        }
        tracing::error!("database: {e}");
        ApiError::internal()
    }
}

pub type ApiResult<T> = Result<T, ApiError>;

/// Battle and Duel run only on the newest gameplay version.
pub const UPDATE_REQUIRED: &str = "update_required";

/// 409 for a phone on an older gameplay version than the server's, in Battle
/// and Duel (Classic and the Daily Run go on working).
pub fn update_required() -> ApiError {
    ApiError::new(StatusCode::CONFLICT, UPDATE_REQUIRED, "Update the game to play Battle and Duel")
}
