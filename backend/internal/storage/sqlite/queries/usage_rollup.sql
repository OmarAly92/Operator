-- name: SaveSessionContext :exec
UPDATE usage_bindings
SET context_used = sqlc.arg(context_used),
    context_window = sqlc.arg(context_window),
    context_at = sqlc.arg(context_at),
    context_model_id = sqlc.arg(context_model_id)
WHERE id = sqlc.arg(id)
  AND sqlc.arg(context_at) IS NOT NULL
  AND (context_at IS NULL OR context_at <= sqlc.arg(context_at));

-- name: GetSessionContext :one
SELECT harness, context_used, context_window, context_at, context_model_id
FROM usage_bindings
WHERE session_id = ? AND context_at IS NOT NULL
ORDER BY context_at DESC
LIMIT 1;

-- name: UsageRollupByDay :many
SELECT substr(CAST(occurred_at AS TEXT), 1, 10) AS bucket_start,
       CAST(COALESCE(SUM(input_tokens), 0) AS INTEGER) AS input_tokens,
       CAST(COALESCE(SUM(uncached_input_tokens), 0) AS INTEGER) AS uncached_input_tokens,
       CAST(COALESCE(SUM(cache_read_tokens), 0) AS INTEGER) AS cache_read_tokens,
       CAST(COALESCE(SUM(cache_write_tokens), 0) AS INTEGER) AS cache_write_tokens,
       CAST(COALESCE(SUM(output_tokens), 0) AS INTEGER) AS output_tokens
FROM model_usage_events
WHERE occurred_at IS NOT NULL AND occurred_at >= ? AND occurred_at < ?
GROUP BY bucket_start
ORDER BY bucket_start;

-- name: UsageRollupByWeek :many
SELECT CAST(date(
           substr(CAST(occurred_at AS TEXT), 1, 10),
           '-' || ((CAST(strftime('%w', substr(CAST(occurred_at AS TEXT), 1, 10)) AS INTEGER) + 6) % 7) || ' days'
       ) AS TEXT) AS bucket_start,
       CAST(COALESCE(SUM(input_tokens), 0) AS INTEGER) AS input_tokens,
       CAST(COALESCE(SUM(uncached_input_tokens), 0) AS INTEGER) AS uncached_input_tokens,
       CAST(COALESCE(SUM(cache_read_tokens), 0) AS INTEGER) AS cache_read_tokens,
       CAST(COALESCE(SUM(cache_write_tokens), 0) AS INTEGER) AS cache_write_tokens,
       CAST(COALESCE(SUM(output_tokens), 0) AS INTEGER) AS output_tokens
FROM model_usage_events
WHERE occurred_at IS NOT NULL AND occurred_at >= ? AND occurred_at < ?
GROUP BY bucket_start
ORDER BY bucket_start;
