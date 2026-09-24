package httpd

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/daemonmeta"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

const (
	mcpToolCallsEvent     = "opr.mcp.tool_calls"
	mcpTelemetryStateFile = "telemetry_mcp_daily.json"
)

// mcpToolCalledRequest is what `opr mcp` reports per Operator tool call
// (cli/mcp_telemetry.go). The session id is used only to count distinct
// sessions and to look up the harness; it is never exported.
type mcpToolCalledRequest struct {
	SessionID string `json:"sessionId"`
	Tool      string `json:"tool"`
	Outcome   string `json:"outcome"`
	State     string `json:"state"`
}

// mcpSessionLookup is the slice of the session service the rollup needs.
type mcpSessionLookup interface {
	Get(ctx context.Context, id domain.SessionID) (domain.Session, error)
}

// mountMCPTelemetry counts Operator MCP tool calls. A call is not an event:
// agents call board tools in loops, so calls are rolled up per UTC day into one
// opr.mcp.tool_calls event per harness, tool, outcome and report state, which
// carries the call count and the number of distinct sessions. A day's rollup
// is emitted by the first call of a later day, or at the next daemon start,
// and persists under DataDir in between so a restart loses no counts.
func mountMCPTelemetry(r chi.Router, cfg config.Config, sink ports.EventSink, sessions mcpSessionLookup) {
	if sink == nil {
		return
	}
	rollup := newMCPToolCallRollup(cfg.DataDir)
	emitMCPToolCallRollup(context.Background(), sink, "", rollup.flushBefore(time.Now()))
	r.Post("/internal/telemetry/mcp-tool-called", func(w http.ResponseWriter, req *http.Request) {
		if !localControlRequest(req) {
			envelope.WriteJSON(w, http.StatusForbidden, map[string]any{
				"status":  "forbidden",
				"service": daemonmeta.ServiceName,
			})
			return
		}
		var body mcpToolCalledRequest
		dec := json.NewDecoder(req.Body)
		dec.DisallowUnknownFields()
		if err := dec.Decode(&body); err != nil {
			envelope.WriteAPIError(w, req, http.StatusBadRequest, "bad_request", "INVALID_JSON", "request body must be valid JSON", nil)
			return
		}
		if !slices.Contains(ports.OperatorMCPToolNames, body.Tool) || (body.Outcome != "ok" && body.Outcome != "error") {
			envelope.WriteAPIError(w, req, http.StatusBadRequest, "bad_request", "INVALID_MCP_TOOL_CALL", "tool must be an Operator MCP tool and outcome ok or error", nil)
			return
		}
		if body.Tool != "session_report" || !slices.Contains(mcpReportStates, body.State) {
			body.State = ""
		}
		harness := "unknown"
		if sessions != nil && body.SessionID != "" {
			if s, err := sessions.Get(req.Context(), domain.SessionID(body.SessionID)); err == nil && s.Harness != "" {
				harness = string(s.Harness)
			}
		}
		flushed := rollup.record(time.Now(), mcpToolCallKey{Harness: harness, Tool: body.Tool, Outcome: body.Outcome, State: body.State}, body.SessionID)
		emitMCPToolCallRollup(req.Context(), sink, middleware.GetReqID(req.Context()), flushed)
		w.WriteHeader(http.StatusAccepted)
	})
}

var mcpReportStates = []string{"needs_you", "ready_for_review", "clear"}

func emitMCPToolCallRollup(ctx context.Context, sink ports.EventSink, requestID string, days []mcpToolCallDay) {
	for _, day := range days {
		occurredAt, _ := time.Parse("2006-01-02", day.Day)
		for _, count := range day.Counts {
			payload := map[string]any{
				"day":      day.Day,
				"harness":  count.Harness,
				"tool":     count.Tool,
				"outcome":  count.Outcome,
				"calls":    count.Calls,
				"sessions": len(count.Sessions),
			}
			if count.State != "" {
				payload["state"] = count.State
			}
			sink.Emit(ctx, ports.TelemetryEvent{
				Name:       mcpToolCallsEvent,
				Source:     "cli",
				OccurredAt: occurredAt.Add(24*time.Hour - time.Second).UTC(),
				Level:      ports.TelemetryLevelInfo,
				RequestID:  requestID,
				Payload:    payload,
			})
		}
	}
}

type mcpToolCallKey struct {
	Harness string `json:"harness"`
	Tool    string `json:"tool"`
	Outcome string `json:"outcome"`
	State   string `json:"state,omitempty"`
}

type mcpToolCallCount struct {
	mcpToolCallKey
	Calls    int      `json:"calls"`
	Sessions []string `json:"sessions"`
}

type mcpToolCallDay struct {
	Day    string             `json:"day"`
	Counts []mcpToolCallCount `json:"counts"`
}

// mcpToolCallRollup holds the current UTC day's counts.
type mcpToolCallRollup struct {
	mu     sync.Mutex
	path   string
	day    string
	counts map[mcpToolCallKey]*mcpToolCallCount
}

func newMCPToolCallRollup(dataDir string) *mcpToolCallRollup {
	r := &mcpToolCallRollup{counts: map[mcpToolCallKey]*mcpToolCallCount{}}
	if dataDir != "" {
		r.path = filepath.Join(dataDir, mcpTelemetryStateFile)
		r.load()
	}
	return r
}

// record counts one call and returns the rollup of an earlier day it closed,
// if any.
func (r *mcpToolCallRollup) record(now time.Time, key mcpToolCallKey, sessionID string) []mcpToolCallDay {
	r.mu.Lock()
	defer r.mu.Unlock()
	flushed := r.flushBeforeLocked(now)
	r.day = telemetryUTCDate(now)
	count := r.counts[key]
	if count == nil {
		count = &mcpToolCallCount{mcpToolCallKey: key}
		r.counts[key] = count
	}
	count.Calls++
	if sessionID != "" && !slices.Contains(count.Sessions, sessionID) {
		count.Sessions = append(count.Sessions, sessionID)
	}
	_ = r.saveLocked()
	return flushed
}

// flushBefore returns and clears the held counts when they belong to a day
// before now's.
func (r *mcpToolCallRollup) flushBefore(now time.Time) []mcpToolCallDay {
	r.mu.Lock()
	defer r.mu.Unlock()
	flushed := r.flushBeforeLocked(now)
	if flushed != nil {
		_ = r.saveLocked()
	}
	return flushed
}

func (r *mcpToolCallRollup) flushBeforeLocked(now time.Time) []mcpToolCallDay {
	if r.day == "" || r.day >= telemetryUTCDate(now) || len(r.counts) == 0 {
		return nil
	}
	day := mcpToolCallDay{Day: r.day, Counts: r.sortedCountsLocked()}
	r.day = ""
	r.counts = map[mcpToolCallKey]*mcpToolCallCount{}
	return []mcpToolCallDay{day}
}

func (r *mcpToolCallRollup) sortedCountsLocked() []mcpToolCallCount {
	out := make([]mcpToolCallCount, 0, len(r.counts))
	for _, count := range r.counts {
		out = append(out, *count)
	}
	sort.Slice(out, func(i, j int) bool {
		a, b := out[i].mcpToolCallKey, out[j].mcpToolCallKey
		if a.Harness != b.Harness {
			return a.Harness < b.Harness
		}
		if a.Tool != b.Tool {
			return a.Tool < b.Tool
		}
		if a.Outcome != b.Outcome {
			return a.Outcome < b.Outcome
		}
		return a.State < b.State
	})
	return out
}

func (r *mcpToolCallRollup) load() {
	b, err := os.ReadFile(r.path)
	if err != nil {
		return
	}
	var st mcpToolCallDay
	if json.Unmarshal(b, &st) != nil {
		return
	}
	r.day = st.Day
	for _, count := range st.Counts {
		c := count
		r.counts[c.mcpToolCallKey] = &c
	}
}

func (r *mcpToolCallRollup) saveLocked() error {
	if r.path == "" {
		return nil
	}
	body, err := json.Marshal(mcpToolCallDay{Day: r.day, Counts: r.sortedCountsLocked()})
	if err != nil {
		return err
	}
	return writeTelemetryStateFile(r.path, body)
}
