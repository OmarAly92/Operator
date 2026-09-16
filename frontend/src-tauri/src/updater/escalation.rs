pub const H48_MS: i64 = 48 * 60 * 60 * 1000;

pub fn evaluate_escalation(staged_at_ms: i64, now_ms: i64) -> bool {
    now_ms - staged_at_ms >= H48_MS
}
