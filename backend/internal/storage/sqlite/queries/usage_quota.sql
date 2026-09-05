-- name: UpsertUsageQuota :exec
-- Newest observation wins. used_percent is not monotonic even inside one window
-- (G4), so this compares observation time and never the percentage.
INSERT INTO usage_quota (
    limit_id, harness, plan_type, observed_at,
    primary_used_percent, primary_window_minutes, primary_resets_at,
    secondary_used_percent, secondary_window_minutes, secondary_resets_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT (limit_id) DO UPDATE SET
    harness = excluded.harness,
    plan_type = excluded.plan_type,
    observed_at = excluded.observed_at,
    primary_used_percent = excluded.primary_used_percent,
    primary_window_minutes = excluded.primary_window_minutes,
    primary_resets_at = excluded.primary_resets_at,
    secondary_used_percent = excluded.secondary_used_percent,
    secondary_window_minutes = excluded.secondary_window_minutes,
    secondary_resets_at = excluded.secondary_resets_at
WHERE excluded.observed_at > usage_quota.observed_at;

-- name: GetLatestUsageQuota :one
SELECT limit_id, harness, plan_type, observed_at,
       primary_used_percent, primary_window_minutes, primary_resets_at,
       secondary_used_percent, secondary_window_minutes, secondary_resets_at
FROM usage_quota
ORDER BY observed_at DESC
LIMIT 1;
