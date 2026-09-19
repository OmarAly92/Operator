# Mobile Subagents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a Claude Code session's subagents on the phone: a live agent card and strip in the parent session, and a tap that opens each agent's own read-only conversation.

**Architecture:** The daemon's transcript supervisor tails each `subagents/agent-<id>.jsonl` file beside the main transcript and stamps every projected block event with `agentId`; the Agent tool's result carries a JSON detail with the agent's id, type, status and totals; the `subagent-stop` hook becomes an `agent_stop` event. The phone scopes `BlocksCubit` by `agentId`, builds an `AgentBlockDetail` from the Agent tool block, joins live tails to cards in a pure `subagentsOf` function, and reuses `BlocksBody` inside a pushed `/session/agent` route.

**Tech Stack:** Go 1.2x (`backend/`), sqlc, OpenAPI code-first; Flutter 3.44.5 / Dart (`packages/mobile`), Cubit, drift-free.

**Spec:** `docs/superpowers/specs/2026-09-19-mobile-subagents-design.md`

## Global Constraints

- Work on `development`; never commit to `master`. Commit only the files you touched (`git add <paths>`, never `git add -A` or `commit -a`): other sessions work in this checkout concurrently.
- Backend gate: `cd backend && go vet ./... && go test ./...`. After any change under `backend/internal/storage/sqlite/queries` or `migrations`: `npm run sqlc` from the repo root and commit `gen/`. After any DTO change in `backend/internal/httpd/controllers/dto.go`: `npm run api` from the repo root and commit `backend/internal/httpd/apispec/openapi.yaml` and `frontend/src/api/schema.ts`.
- Mobile gate: `cd packages/mobile && flutter analyze` must print `No issues found!` and `flutter test` must pass. No `freezed`, no `json_serializable`, no `Bloc` with events, no `flutter_screenutil` in feature code, no `LocaleKeys`; user-facing copy is inline English. Models are hand-written with nullable fields and `fromJson`.
- Do not write code comments (user rule). Doc comments already in touched files may stay.
- Wire contract: `agentId` empty or absent means the main conversation. `GET /sessions/{id}/blocks` without `agentId` returns main-only rows, exactly today's behaviour.
- Colors and type come from `context.skin` and `AppTextStyle` only; spacing takes raw ints.

---

## File map

Backend (create / modify):
- `backend/internal/storage/sqlite/migrations/0115_block_events_agent.sql` — create.
- `backend/internal/storage/sqlite/queries/block_events.sql` — add `agent_id`, `detail` columns to insert/select, agent filter.
- `backend/internal/service/blockevent/types.go`, `service.go` — `AgentID`, `Detail` on `Record`; `RecordTranscript` copies them; `History*` take `agentID`.
- `backend/internal/storage/sqlite/store/block_event_store.go` — round-trip the two columns, filter.
- `backend/internal/domain/blockevent.go` — `BlockEventAgentStop`, `AgentID`/`Detail` on `BlockTranscriptEvent`.
- `backend/internal/adapters/agent/claudecode/transcript.go` — `MapSidechainRecord`, Agent result detail.
- `backend/internal/adapters/agent/blocktranscript/dispatch.go` — `MapSidechain`.
- `backend/internal/observe/transcript/supervisor.go`, `tail.go` — subagent tails.
- `backend/internal/adapters/agent/blockdispatch/dispatch.go` — `subagent-stop` → `agent_stop`.
- `backend/internal/ports/runtime_observations.go`, `backend/internal/httpd/controllers/sessions.go`, `dto.go` — `AgentID` on the signal, `agentId` on the view and query.
- `testdata/transcripts/claude_code_subagent.jsonl` + `.expected.json` — fixture from a real agent file.

Mobile (create / modify):
- `lib/feature/blocks/data/model/block_event_model.dart`, `params/get_session_blocks_params.dart`, `data_source/blocks_remote_data_source.dart`.
- `lib/feature/blocks/logic/session_block.dart` — `AgentBlockDetail`, `agentId`.
- `lib/feature/blocks/logic/block_assembly.dart` — Agent detail, `agent_stop`.
- `lib/feature/blocks/logic/subagents.dart` — create: `SubagentSummary`, `SubagentEntry`, `subagentsOf`.
- `lib/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart` — `BlocksScope`, agent filter, summaries.
- `lib/core/utils/service_locator.dart`, `lib/core/app_routes/app_router.dart`, `routes_strings.dart`, `lib/feature/sessions/presentation/session_route/ui/session_route_screen.dart` — scope param, new route.
- `lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart` — `RailKind.agent`, `_AgentBody`.
- `lib/feature/blocks/presentation/blocks_screen/ui/widgets/subagent_strip.dart` — create.
- `lib/feature/blocks/presentation/subagent_screen/ui/subagent_screen.dart` — create.
- `lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_body.dart` — mount the strip.

---

### Task 1: Block events carry `agent_id` and `detail`

**Files:**
- Create: `backend/internal/storage/sqlite/migrations/0115_block_events_agent.sql`
- Modify: `backend/internal/storage/sqlite/queries/block_events.sql`
- Modify: `backend/internal/service/blockevent/types.go:18-47`
- Modify: `backend/internal/service/blockevent/service.go:100-135, 150-170`
- Modify: `backend/internal/storage/sqlite/store/block_event_store.go`
- Modify: `backend/internal/domain/blockevent.go:13-45, 61-70`
- Test: `backend/internal/storage/sqlite/store/block_event_store_test.go` (existing file; add a test), `backend/internal/service/blockevent/service_test.go`

**Interfaces:**
- Produces: `blockevent.Record{AgentID string; Detail string}`; `Store.SelectBlockEventsBySession(ctx, sessionID, agentID string, afterSeq int64, limit int)`; `Store.SelectBlockEventsBeforeSeq(ctx, sessionID, agentID string, beforeSeq int64, limit int)`; `Service.History(ctx, id, agentID string, afterSeq int64, limit int)`; `Service.HistoryBefore(ctx, id, agentID string, beforeSeq int64, limit int)`; `domain.BlockTranscriptEvent{AgentID, Detail string}`; `domain.BlockEventAgentStop BlockEventKind = "agent_stop"`.

- [ ] **Step 1: Write the store round-trip test**

Open `backend/internal/storage/sqlite/store/block_event_store_test.go`, find how existing tests build a store (search `newTestStore` or the first `InsertBlockEvent` call) and add, using the same constructor:

```go
func TestBlockEventStoreScopesRowsByAgent(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	base := blockevent.Record{SessionID: "s1", Kind: domain.BlockEventAssistantText, CreatedAt: time.Now().UTC()}
	if _, err := s.InsertBlockEvent(ctx, base); err != nil {
		t.Fatal(err)
	}
	agent := base
	agent.AgentID = "a1"
	agent.Detail = `{"agentId":"a1"}`
	if _, err := s.InsertBlockEvent(ctx, agent); err != nil {
		t.Fatal(err)
	}
	main, err := s.SelectBlockEventsBySession(ctx, "s1", "", 0, 10)
	if err != nil || len(main) != 1 || main[0].AgentID != "" {
		t.Fatalf("main rows = %+v, %v; want exactly the unscoped row", main, err)
	}
	scoped, err := s.SelectBlockEventsBySession(ctx, "s1", "a1", 0, 10)
	if err != nil || len(scoped) != 1 || scoped[0].AgentID != "a1" || scoped[0].Detail != `{"agentId":"a1"}` {
		t.Fatalf("agent rows = %+v, %v; want the a1 row with its detail", scoped, err)
	}
	before, err := s.SelectBlockEventsBeforeSeq(ctx, "s1", "a1", scoped[0].Seq+1, 10)
	if err != nil || len(before) != 1 || before[0].AgentID != "a1" {
		t.Fatalf("before rows = %+v, %v", before, err)
	}
}
```

- [ ] **Step 2: Run it to see it fail to compile**

Run: `cd backend && go test ./internal/storage/sqlite/store/ -run TestBlockEventStoreScopesRowsByAgent`
Expected: compile error, `rec.AgentID undefined` / too many arguments.

- [ ] **Step 3: Migration and queries**

Create `backend/internal/storage/sqlite/migrations/0115_block_events_agent.sql` (copy the up/down marker style from `0114_tickets.sql`):

```sql
-- +goose Up
ALTER TABLE block_events ADD COLUMN agent_id TEXT NOT NULL DEFAULT '';
ALTER TABLE block_events ADD COLUMN detail TEXT NOT NULL DEFAULT '';
CREATE INDEX block_events_session_agent_seq ON block_events (session_id, agent_id, seq);

-- +goose Down
DROP INDEX IF EXISTS block_events_session_agent_seq;
ALTER TABLE block_events DROP COLUMN detail;
ALTER TABLE block_events DROP COLUMN agent_id;
```

If `0114_tickets.sql` uses a different marker convention than goose, match it exactly.

Edit `backend/internal/storage/sqlite/queries/block_events.sql`:

```sql
-- name: InsertBlockEvent :one
INSERT INTO block_events (
    session_id, source_id, kind, raw_event, harness, tool_name, tool_use_id,
    tool_input, text, redacted_spans, error_type, hook_version, truncated_lines,
    source, interaction_id, agent_id, detail, created_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
RETURNING *;

-- name: SelectBlockEventsBySession :many
SELECT *
FROM block_events
WHERE session_id = ? AND agent_id = ? AND seq > ?
ORDER BY seq
LIMIT ?;

-- name: SelectBlockEventsBeforeSeq :many
SELECT * FROM (
  SELECT seq, session_id, source_id, kind, raw_event, harness, tool_name, tool_use_id,
         text, redacted_spans, tool_input, error_type, hook_version, truncated_lines,
         source, interaction_id, agent_id, detail, created_at
  FROM block_events
  WHERE session_id = ? AND agent_id = ? AND seq < ?
  ORDER BY seq DESC
  LIMIT ?
) ORDER BY seq ASC;
```

Leave `TrimBlockEventsForSession` and `SelectLatestTurnModels` unchanged (trim keeps the newest N rows across all agents of a session, which is acceptable). Run `npm run sqlc` from the repo root.

- [ ] **Step 4: Record, store, service, domain**

`backend/internal/service/blockevent/types.go`: add to `Record` after `InteractionID`:

```go
	AgentID        string                  `json:"agentId,omitempty"`
	Detail         string                  `json:"detail,omitempty"`
```

and change the `Store` interface:

```go
	SelectBlockEventsBySession(ctx context.Context, sessionID, agentID string, afterSeq int64, limit int) ([]Record, error)
	SelectBlockEventsBeforeSeq(ctx context.Context, sessionID, agentID string, beforeSeq int64, limit int) ([]Record, error)
```

`backend/internal/storage/sqlite/store/block_event_store.go`: in `InsertBlockEvent` add `AgentID: rec.AgentID, Detail: rec.Detail,` to the params; in every place a `gen.BlockEvent` row is mapped to a `Record` (three sites, lines ~44, ~97, ~134) add `AgentID: row.AgentID, Detail: row.Detail,`; thread `agentID` into the two select methods and pass it to the generated params (`AgentID: agentID`).

`backend/internal/domain/blockevent.go`: add `BlockEventAgentStop BlockEventKind = "agent_stop"` to the const block, add it to `ParseBlockEventKind`'s case list, and extend `BlockTranscriptEvent` with:

```go
	AgentID   string
	Detail    string
```

`backend/internal/service/blockevent/service.go`: in `RecordTranscript` add `AgentID: ev.AgentID, Detail: ev.Detail,` to the `Record`; change `History` and `HistoryBefore` to

```go
func (s *Service) History(ctx context.Context, sessionID domain.SessionID, agentID string, afterSeq int64, limit int) ([]Record, error) {
	if limit <= 0 || limit > s.retain {
		limit = s.retain
	}
	return s.store.SelectBlockEventsBySession(ctx, string(sessionID), agentID, afterSeq, limit)
}

func (s *Service) HistoryBefore(ctx context.Context, sessionID domain.SessionID, agentID string, beforeSeq int64, limit int) ([]Record, error) {
	if limit <= 0 || limit > s.retain {
		limit = s.retain
	}
	return s.store.SelectBlockEventsBeforeSeq(ctx, string(sessionID), agentID, beforeSeq, limit)
}
```

Fix every caller and fake that `go build ./... && go vet ./...` reports (search `History(` / `HistoryBefore(` / `SelectBlockEventsBySession(` under `backend/internal`, including `replay.go`, `_test.go` fakes and the controller, which Task 5 finishes). For callers that are not agent-aware yet, pass `""`.

- [ ] **Step 5: Run the store and service tests**

Run: `cd backend && go build ./... && go test ./internal/storage/... ./internal/service/blockevent/`
Expected: PASS, including the new test.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/storage/sqlite/migrations/0115_block_events_agent.sql backend/internal/storage/sqlite/queries/block_events.sql backend/internal/storage/sqlite/gen backend/internal/storage/sqlite/store backend/internal/service/blockevent backend/internal/domain/blockevent.go backend/internal/httpd/controllers
# then `git status --short backend` and add any other file the signature change touched
git commit -m "feat(blocks): scope block events by agent id and carry a detail payload"
```

---

### Task 2: Sidechain mapper and Agent result detail

**Files:**
- Modify: `backend/internal/adapters/agent/claudecode/transcript.go:11-24, 57-83, 169-187`
- Modify: `backend/internal/adapters/agent/blocktranscript/dispatch.go`
- Create: `testdata/transcripts/claude_code_subagent.jsonl`, `testdata/transcripts/claude_code_subagent.expected.json`
- Test: `backend/internal/adapters/agent/claudecode/transcript_test.go`, `backend/internal/adapters/agent/blocktranscript/dispatch_test.go`

**Interfaces:**
- Produces: `claudecode.MapSidechainRecord(agentID string, line []byte) ([]domain.BlockTranscriptEvent, bool)`; `blocktranscript.MapSidechain(harness, agentID string, line []byte) ([]domain.BlockTranscriptEvent, bool)`; `blocktranscript.SupportsSidechain(harness string) bool`. Agent `tool_result` events carry `Detail` JSON `{"agentId","agentType","status","resolvedModel","totalDurationMs","totalToolUseCount","totalTokens"}`.

- [ ] **Step 1: Build the fixture from a real agent file**

Pick the newest `~/.claude/projects/*/*/subagents/agent-*.jsonl` (Python, not the shell: the directory names start with `-`). Copy its first 12 lines to `testdata/transcripts/claude_code_subagent.jsonl`, then replace every `cwd`, `gitBranch`, absolute path and prompt body with short neutral stand-ins (`/repo`, `main`, `Implement task 1`), keeping the JSON shape, `agentId`, `isSidechain`, `type`, `uuid` and content block types intact. The first line must remain a `user` record whose `message.content` is the prompt string (or a one-element text array). Write `claude_code_subagent.expected.json` in the shape `transcriptFixture` in `transcript_test.go:11-25` reads, with `"known": true` on every line and the events you expect: line 1 → `[{"kind":"prompt_submit","sourceId":"*","text":"<the prompt>"}]`; an `attachment` line → `[]`; an `assistant` text line → `turn_model` then `assistant_text`; a `tool_use` line → `tool_start` with `toolName`/`toolUseId`; a `tool_result` user line → `tool_result`.

- [ ] **Step 2: Write the failing tests**

Append to `backend/internal/adapters/agent/claudecode/transcript_test.go`:

```go
func TestMapSidechainRecordFixture(t *testing.T) {
	dir := filepath.Join("..", "..", "..", "..", "..", "testdata", "transcripts")
	raw, err := os.ReadFile(filepath.Join(dir, "claude_code_subagent.expected.json"))
	if err != nil {
		t.Fatal(err)
	}
	var fixture transcriptFixture
	if err := json.Unmarshal(raw, &fixture); err != nil {
		t.Fatal(err)
	}
	file, err := os.Open(filepath.Join(dir, "claude_code_subagent.jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = file.Close() }()
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 1<<20), 1<<20)
	index := 0
	for scanner.Scan() {
		want := fixture.Lines[index]
		got, known := MapSidechainRecord("a17c0aebd85b89c55", scanner.Bytes())
		if known != want.Known || len(got) != len(want.Events) {
			t.Fatalf("line %d: known=%v events=%+v; want known=%v %d events", index+1, known, got, want.Known, len(want.Events))
		}
		for i, expected := range want.Events {
			if string(got[i].Kind) != expected.Kind || got[i].Text != expected.Text || got[i].ToolName != expected.ToolName {
				t.Fatalf("line %d event %d = %+v want %+v", index+1, i, got[i], expected)
			}
			if got[i].AgentID != "a17c0aebd85b89c55" {
				t.Fatalf("line %d event %d has agent id %q", index+1, i, got[i].AgentID)
			}
		}
		if mainEvents, _ := MapTranscriptRecord(scanner.Bytes()); len(mainEvents) != 0 {
			t.Fatalf("line %d: the main mapper must still drop sidechain records, got %+v", index+1, mainEvents)
		}
		index++
	}
}

func TestSidechainMapperEmitsPromptSubmitOnlyForTheFirstUserText(t *testing.T) {
	first := `{"type":"user","isSidechain":true,"agentId":"a1","uuid":"u1","message":{"role":"user","content":"Implement task 1"}}`
	events, ok := MapSidechainRecord("a1", []byte(first))
	if !ok || len(events) != 1 || events[0].Kind != domain.BlockEventPromptSubmit || events[0].Text != "Implement task 1" {
		t.Fatalf("first user record = %+v, %v", events, ok)
	}
	result := `{"type":"user","isSidechain":true,"agentId":"a1","uuid":"u2","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_1","content":"ok"}]}}`
	events, _ = MapSidechainRecord("a1", []byte(result))
	if len(events) != 1 || events[0].Kind != domain.BlockEventToolResult {
		t.Fatalf("tool result record = %+v", events)
	}
}

func TestAgentToolResultCarriesTheAgentDetail(t *testing.T) {
	line := `{"type":"user","uuid":"u9","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_A","content":"done"}]},"toolUseResult":{"agentId":"a17c","agentType":"general-purpose","status":"completed","resolvedModel":"claude-sonnet-5","totalDurationMs":61234,"totalToolUseCount":7,"totalTokens":12345,"usage":{"input_tokens":1}}}`
	events, ok := MapTranscriptRecord([]byte(line))
	if !ok || len(events) != 1 {
		t.Fatalf("events = %+v, %v", events, ok)
	}
	var detail map[string]any
	if err := json.Unmarshal([]byte(events[0].Detail), &detail); err != nil {
		t.Fatalf("detail %q: %v", events[0].Detail, err)
	}
	if detail["agentId"] != "a17c" || detail["agentType"] != "general-purpose" || detail["status"] != "completed" || detail["totalToolUseCount"] != float64(7) {
		t.Fatalf("detail = %v", detail)
	}
	if _, present := detail["usage"]; present {
		t.Fatal("usage must not be forwarded")
	}
	plain := `{"type":"user","uuid":"u10","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_B","content":"x"}]},"toolUseResult":{"stdout":"x"}}`
	events, _ = MapTranscriptRecord([]byte(plain))
	if events[0].Detail != "" {
		t.Fatalf("non-agent result must carry no detail, got %q", events[0].Detail)
	}
}
```

Add `"github.com/OmarAly92/operator/backend/internal/domain"` to the test imports.

Append to `backend/internal/adapters/agent/blocktranscript/dispatch_test.go`:

```go
func TestMapSidechainIsClaudeCodeOnly(t *testing.T) {
	if !SupportsSidechain("claude-code") || SupportsSidechain("codex") {
		t.Fatal("sidechain projection is claude-code only")
	}
	line := []byte(`{"type":"user","isSidechain":true,"agentId":"a1","uuid":"u1","message":{"content":"go"}}`)
	events, ok := MapSidechain("claude-code", "a1", line)
	if !ok || len(events) != 1 || events[0].AgentID != "a1" {
		t.Fatalf("MapSidechain = %+v, %v", events, ok)
	}
	if events, ok := MapSidechain("codex", "a1", line); ok || len(events) != 0 {
		t.Fatal("codex has no sidechain mapper")
	}
}
```

- [ ] **Step 3: Run to verify failure**

Run: `cd backend && go test ./internal/adapters/agent/claudecode/ ./internal/adapters/agent/blocktranscript/`
Expected: compile errors for `MapSidechainRecord`, `MapSidechain`, `SupportsSidechain`, `Detail`.

- [ ] **Step 4: Implement the mapper**

In `transcript.go`, extend the record struct:

```go
type claudeTranscriptRecord struct {
	Type            string          `json:"type"`
	Subtype         string          `json:"subtype"`
	UUID            string          `json:"uuid"`
	IsSidechain     bool            `json:"isSidechain"`
	AgentID         string          `json:"agentId"`
	Content         json.RawMessage `json:"content"`
	ToolUseResult   json.RawMessage `json:"toolUseResult"`
	CompactMetadata struct {
		Trigger string `json:"trigger"`
	} `json:"compactMetadata"`
	Message struct {
		Model   string          `json:"model"`
		Content json.RawMessage `json:"content"`
	} `json:"message"`
}
```

Refactor `MapTranscriptRecord` into a shared body and add the sidechain entry point:

```go
func MapTranscriptRecord(line []byte) ([]domain.BlockTranscriptEvent, bool) {
	var rec claudeTranscriptRecord
	if err := json.Unmarshal(line, &rec); err != nil {
		return nil, false
	}
	if rec.IsSidechain {
		return nil, true
	}
	return mapClaudeRecord(rec, false)
}

func MapSidechainRecord(agentID string, line []byte) ([]domain.BlockTranscriptEvent, bool) {
	var rec claudeTranscriptRecord
	if err := json.Unmarshal(line, &rec); err != nil {
		return nil, false
	}
	events, ok := mapClaudeRecord(rec, true)
	for i := range events {
		events[i].AgentID = agentID
	}
	return events, ok
}

func mapClaudeRecord(rec claudeTranscriptRecord, sidechain bool) ([]domain.BlockTranscriptEvent, bool) {
	switch rec.Type {
	case "assistant":
		return claudeAssistantEvents(rec), true
	case "user":
		events := claudeUserEvents(rec)
		if sidechain && len(events) == 0 {
			if prompt := strings.TrimSpace(claudeFlattenText(rec.Message.Content)); prompt != "" {
				events = append(events, domain.BlockTranscriptEvent{
					Kind:     domain.BlockEventPromptSubmit,
					SourceID: rec.UUID,
					Text:     prompt,
				})
			}
		}
		return events, true
	case "system":
		if rec.Subtype != "compact_boundary" {
			return nil, true
		}
		return []domain.BlockTranscriptEvent{{
			Kind:     domain.BlockEventCompaction,
			SourceID: rec.UUID,
			Text:     claudeCompactionText(rec),
		}}, true
	default:
		if _, ignored := claudeIgnoredRecordTypes[rec.Type]; ignored {
			return nil, true
		}
		return nil, false
	}
}
```

A sidechain `user` record with plain text but no `tool_result` is the agent's prompt; Claude Code writes it once per agent, so "first user text" and "user text with no tool_result" coincide in practice, and any later text-only user record (a harness note) would render as a second prompt bubble, which is acceptable.

In `claudeUserEvents`, after building `event` and before `events = append(...)`, attach the detail:

```go
		if detail := claudeAgentResultDetail(rec.ToolUseResult); detail != "" {
			event.Detail = detail
		}
```

and add:

```go
func claudeAgentResultDetail(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}
	var result struct {
		AgentID           string `json:"agentId"`
		AgentType         string `json:"agentType"`
		Status            string `json:"status"`
		ResolvedModel     string `json:"resolvedModel"`
		TotalDurationMs   int64  `json:"totalDurationMs"`
		TotalToolUseCount int    `json:"totalToolUseCount"`
		TotalTokens       int64  `json:"totalTokens"`
	}
	if err := json.Unmarshal(raw, &result); err != nil || result.AgentID == "" {
		return ""
	}
	encoded, err := json.Marshal(map[string]any{
		"agentId":           result.AgentID,
		"agentType":         result.AgentType,
		"status":            result.Status,
		"resolvedModel":     result.ResolvedModel,
		"totalDurationMs":   result.TotalDurationMs,
		"totalToolUseCount": result.TotalToolUseCount,
		"totalTokens":       result.TotalTokens,
	})
	if err != nil {
		return ""
	}
	return string(encoded)
}
```

In `blocktranscript/dispatch.go` add:

```go
type SidechainMapFunc func(agentID string, line []byte) ([]domain.BlockTranscriptEvent, bool)

var SidechainMappers = map[string]SidechainMapFunc{
	"claude-code": claudecode.MapSidechainRecord,
}

func SupportsSidechain(harness string) bool {
	_, found := SidechainMappers[harness]
	return found
}

func MapSidechain(harness, agentID string, line []byte) ([]domain.BlockTranscriptEvent, bool) {
	mapper, found := SidechainMappers[harness]
	if !found {
		return nil, false
	}
	return mapper(agentID, line)
}
```

- [ ] **Step 5: Run the tests**

Run: `cd backend && go test ./internal/adapters/agent/...`
Expected: PASS. If the fixture expectations mismatch, fix the expected JSON to what the real file contains, never the mapper, unless the mapper is wrong.

- [ ] **Step 6: Commit**

```bash
git add testdata/transcripts/claude_code_subagent.jsonl testdata/transcripts/claude_code_subagent.expected.json backend/internal/adapters/agent/claudecode/transcript.go backend/internal/adapters/agent/claudecode/transcript_test.go backend/internal/adapters/agent/blocktranscript/dispatch.go backend/internal/adapters/agent/blocktranscript/dispatch_test.go
git commit -m "feat(transcript): map Claude Code subagent transcripts and the Agent result detail"
```

---

### Task 3: Supervisor tails subagent files

**Files:**
- Modify: `backend/internal/observe/transcript/tail.go:32-40, 42-112`
- Modify: `backend/internal/observe/transcript/supervisor.go:153-227, 260-274, 285-291`
- Test: `backend/internal/observe/transcript/supervisor_test.go`

**Interfaces:**
- Consumes: `blocktranscript.MapSidechain`, `blocktranscript.SupportsSidechain` (Task 2).
- Produces: `tail.agentID string`; `offsetKey(sessionID domain.SessionID, agentID string) string` returning `"<id>"` or `"<id>#<agentID>"`; `subagentPaths(mainPath string) []string`.

- [ ] **Step 1: Write the failing test**

Append to `supervisor_test.go`:

```go
const sidechainPrompt = `{"type":"user","isSidechain":true,"agentId":"x1","uuid":"su-1","message":{"role":"user","content":"Implement task 1"}}`

func TestReconcileTailsSubagentFilesBesideTheMainTranscript(t *testing.T) {
	root := t.TempDir()
	configDir := filepath.Join(root, "config")
	sessionDir := filepath.Join(configDir, "projects", "p")
	path := writeTranscript(t, sessionDir, "sess-1.jsonl")
	appendLines(t, path, assistantLine)

	sessions := &fakeSessions{sessions: []domain.SessionRecord{session("s-1", "claude-code", path, false)}}
	sink := &fakeSink{}
	offsets := &fakeOffsets{}
	sup := newSupervisor(t, sessions, sink, offsets, newFakeWatcher(), configDir)

	sup.reconcile(context.Background())
	if len(sup.tails) != 1 {
		t.Fatalf("expected one tail before the agent file exists, got %d", len(sup.tails))
	}

	agentDir := filepath.Join(sessionDir, "sess-1", "subagents")
	if err := os.MkdirAll(agentDir, 0o700); err != nil {
		t.Fatal(err)
	}
	agentPath := filepath.Join(agentDir, "agent-x1.jsonl")
	appendLines(t, agentPath, sidechainPrompt, assistantLine)

	sup.reconcile(context.Background())
	sup.pumpAll(context.Background())

	var agentEvents, mainEvents int
	for _, ev := range sink.recorded() {
		switch ev.event.AgentID {
		case "x1":
			agentEvents++
		case "":
			mainEvents++
		default:
			t.Fatalf("unexpected agent id %q", ev.event.AgentID)
		}
	}
	if agentEvents < 2 || mainEvents < 1 {
		t.Fatalf("agent events = %d, main events = %d", agentEvents, mainEvents)
	}
	if offsets.lastKey != "s-1#x1" && offsets.lastKey != "s-1" {
		t.Fatalf("offset key = %q", offsets.lastKey)
	}

	sessions.sessions[0].IsTerminated = true
	ended := sup.reconcile(context.Background())
	if len(ended) != 2 {
		t.Fatalf("expected both tails retired with the session, got %d", len(ended))
	}
}
```

Check `recordedEvent` in `tail_test.go` for the field that holds the event (adjust `ev.event`), and extend `fakeOffsets.UpsertTranscriptOffset` to record the key it was given:

```go
func (o *fakeOffsets) UpsertTranscriptOffset(_ context.Context, key, path string, offset int64, _ time.Time) error {
	o.writes++
	o.lastKey = key
	o.path = path
	o.offset = offset
	return nil
}
```

with a `lastKey string` field. Keep the existing body lines that were already there.

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && go test ./internal/observe/transcript/ -run TestReconcileTailsSubagentFiles`
Expected: FAIL at "expected both tails retired" or the agent-event count (only one tail exists).

- [ ] **Step 3: Implement subagent tails**

`tail.go`: add `agentID string` to `tail`, and

```go
func offsetKey(sessionID domain.SessionID, agentID string) string {
	if agentID == "" {
		return string(sessionID)
	}
	return string(sessionID) + "#" + agentID
}
```

In `pump`, replace the mapping call and both offset writes:

```go
		var events []domain.BlockTranscriptEvent
		var known bool
		if t.agentID == "" {
			events, known = blocktranscript.Map(t.harness, record)
		} else {
			events, known = blocktranscript.MapSidechain(t.harness, t.agentID, record)
		}
```

and `offsets.UpsertTranscriptOffset(ctx, offsetKey(t.sessionID, t.agentID), t.path, t.offset, now())` in both places.

`supervisor.go`: change `tails map[domain.SessionID]*tail` to `tails map[string]*tail` keyed by `offsetKey(sessionID, agentID)` (the main tail keeps the plain session id as key, so existing tests that index `sup.tails["s-1"]` keep working; update any test that ranges and asserts on `domain.SessionID` keys). In `reconcile`, right after `s.tails[rec.ID] = s.newTail(ctx, rec, path)` / the `continue` for an already tracked main path, add subagent discovery for every live session (not only new ones):

```go
		if blocktranscript.SupportsSidechain(string(rec.Harness)) {
			for _, agentPath := range subagentPaths(path) {
				agentID := strings.TrimSuffix(strings.TrimPrefix(filepath.Base(agentPath), "agent-"), ".jsonl")
				key := offsetKey(rec.ID, agentID)
				seenKeys[key] = struct{}{}
				paths = append(paths, agentPath)
				if _, tracked := s.tails[key]; tracked {
					continue
				}
				s.tails[key] = s.newAgentTail(ctx, rec, agentID, agentPath)
			}
		}
```

Track liveness with a `seenKeys map[string]struct{}` alongside the existing `seen` (add the main key `string(rec.ID)` to it wherever `seen[rec.ID]` is set), and replace the retirement loop with:

```go
	for key, tracked := range s.tails {
		if _, live := seenKeys[key]; !live {
			if _, sessionAlive := alive[tracked.sessionID]; !sessionAlive || terminated[tracked.sessionID] {
				ended = append(ended, tracked)
			}
			delete(s.tails, key)
		}
	}
```

where `terminated` is a `map[domain.SessionID]bool` filled in the loop when `rec.IsTerminated`. Move the existing `if tracked && rec.IsTerminated { ended = append(ended, existing) }` into this rule so a terminated session retires all its tails exactly once (drop the old per-session `ended` append). Add:

```go
func subagentPaths(mainPath string) []string {
	dir := filepath.Join(filepath.Dir(mainPath), strings.TrimSuffix(filepath.Base(mainPath), ".jsonl"), "subagents")
	matches, err := filepath.Glob(filepath.Join(dir, "agent-*.jsonl"))
	if err != nil {
		return nil
	}
	sort.Strings(matches)
	return matches
}

func (s *Supervisor) newAgentTail(ctx context.Context, rec domain.SessionRecord, agentID, path string) *tail {
	created := &tail{sessionID: rec.ID, harness: string(rec.Harness), path: path, agentID: agentID}
	if s.deps.Offsets == nil {
		return created
	}
	storedPath, offset, found, err := s.deps.Offsets.GetTranscriptOffset(ctx, offsetKey(rec.ID, agentID))
	if err != nil {
		s.deps.Logger.Warn("transcript cursor read", "session", rec.ID, "agent", agentID, "err", err)
		return created
	}
	if found && storedPath == path {
		created.offset = offset
	}
	return created
}
```

Import `path/filepath` and `strings`. `pumpPath` already matches by path and needs no change. The final drain in `Start`/`tick` that pumps `ended` tails keeps working because `ended` is `[]*tail`.

- [ ] **Step 4: Run the package tests**

Run: `cd backend && go test ./internal/observe/transcript/`
Expected: PASS, all existing tests included.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/observe/transcript
git commit -m "feat(transcript): tail Claude Code subagent transcripts with per-agent cursors"
```

---

### Task 4: `subagent-stop` becomes `agent_stop`

**Files:**
- Modify: `backend/internal/adapters/agent/blockdispatch/dispatch.go:61`
- Modify: `backend/internal/ports/runtime_observations.go:43-60`
- Modify: `backend/internal/httpd/controllers/sessions.go:1760-1778`
- Modify: `backend/internal/service/blockevent/service.go:60-99`
- Test: `backend/internal/adapters/agent/blockdispatch/dispatch_test.go`, `backend/internal/service/blockevent/service_test.go`

**Interfaces:**
- Produces: `ports.ActivitySignal.AgentID string`; hook records with `Kind == "agent_stop"` carry `AgentID` and `SourceID == AgentID`.

- [ ] **Step 1: Failing tests**

`dispatch_test.go`:

```go
func TestSubagentStopIsAnAgentStopEvent(t *testing.T) {
	got := Map("claude-code", "subagent-stop")
	if got.Drop || got.Kind != domain.BlockEventAgentStop {
		t.Fatalf("subagent-stop = %+v; want agent_stop, not dropped", got)
	}
}
```

`service_test.go` (use the package's existing fake store and `New`/constructor; look at the first test for the pattern):

```go
func TestRecordStampsTheAgentIDOnAnAgentStop(t *testing.T) {
	store := &fakeStore{}
	svc := newTestService(t, store)
	sig := ports.ActivitySignal{Valid: true, Event: "subagent-stop", AgentID: "a1", LatestAssistantUpdate: "done"}
	if err := svc.Record(context.Background(), "s1", "claude-code", sig); err != nil {
		t.Fatal(err)
	}
	rec := store.inserted[len(store.inserted)-1]
	if rec.Kind != domain.BlockEventAgentStop || rec.AgentID != "a1" || rec.SourceID != "a1" || rec.Text != "done" {
		t.Fatalf("record = %+v", rec)
	}
}
```

Adjust `fakeStore`, `newTestService` and `inserted` to the names the file actually uses.

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && go test ./internal/adapters/agent/blockdispatch/ ./internal/service/blockevent/`
Expected: FAIL (`drop: true`; `AgentID` undefined).

- [ ] **Step 3: Implement**

`dispatch.go`: replace `"subagent-stop": {drop: true},` with `"subagent-stop": {kind: domain.BlockEventAgentStop},` in `claudeCodeEvents`. Update the comment block above it only by deleting the sentence about subagent traffic being excluded.

`ports/runtime_observations.go`: add `AgentID string` to `ActivitySignal` after `AgentSessionID`.

`controllers/sessions.go` in the activity handler, after the `sig := ports.ActivitySignal{...}` literal:

```go
	if in.Usage != nil && strings.TrimSpace(in.Event) == "subagent-stop" {
		sig.AgentID = capActivityMeta(domain.SanitizeControlChars(strings.TrimSpace(in.Usage.SubagentID)))
	}
```

(`in.Usage.SubagentID` already exists: `usageHookMetadata.SubagentID` is decoded from the hook's `agent_id`. Confirm the DTO field name in `dto.go`'s activity request; if the usage struct there names it differently, use that name.)

`service/blockevent/service.go` `Record`: after computing `sourceID`, add

```go
	if sig.AgentID != "" {
		sourceID = sig.AgentID
	}
```

and add `AgentID: sig.AgentID,` to the `Record` literal.

- [ ] **Step 4: Run tests**

Run: `cd backend && go test ./internal/adapters/agent/blockdispatch/ ./internal/service/blockevent/ ./internal/httpd/controllers/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/adapters/agent/blockdispatch backend/internal/ports/runtime_observations.go backend/internal/httpd/controllers/sessions.go backend/internal/service/blockevent
git commit -m "feat(blocks): record subagent-stop as an agent_stop event with its agent id"
```

---

### Task 5: `agentId` on the blocks route and view

**Files:**
- Modify: `backend/internal/httpd/controllers/sessions.go:145-146, 1233-1279`
- Modify: `backend/internal/httpd/controllers/dto.go:306-364`
- Modify: `backend/internal/httpd/apispec/specgen/build.go` (only if the query parameter registry lists parameters per operation; search for `afterSeq` there and add `agentId` beside it)
- Test: `backend/internal/httpd/controllers/sessions_block_events_test.go:182-330`

**Interfaces:**
- Consumes: `Service.History(ctx, id, agentID, afterSeq, limit)` (Task 1).
- Produces: `BlockEventView.AgentID string json:"agentId,omitempty"`, `BlockEventView.Detail string json:"detail,omitempty"`; query `?agentId=`.

- [ ] **Step 1: Failing test**

Extend `fakeBlockEventHistory` with `gotAgent string`, set it in both methods from the new parameter, and add:

```go
func TestListBlockEventsScopesByAgentAndServesTheView(t *testing.T) {
	hist := &fakeBlockEventHistory{recs: []blockeventsvc.Record{{
		Seq: 7, SessionID: "s1", Kind: domain.BlockEventToolResult, AgentID: "a1", Detail: `{"agentId":"a1"}`,
	}}}
	srv := newBlockHistoryTestServer(t, hist)
	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/s1/blocks?agentId=a1&afterSeq=0", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d body = %s", status, body)
	}
	if hist.gotAgent != "a1" {
		t.Fatalf("agent filter not passed: %q", hist.gotAgent)
	}
	var got struct {
		Blocks []map[string]any `json:"blocks"`
	}
	mustJSON(t, body, &got)
	if got.Blocks[0]["agentId"] != "a1" || got.Blocks[0]["detail"] != `{"agentId":"a1"}` {
		t.Fatalf("view = %v", got.Blocks[0])
	}

	hist.gotAgent = "unset"
	if _, status, _ = doRequest(t, srv, http.MethodGet, "/api/v1/sessions/s1/blocks", ""); status != http.StatusOK || hist.gotAgent != "" {
		t.Fatalf("default must be main-only: status=%d agent=%q", status, hist.gotAgent)
	}
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && go test ./internal/httpd/controllers/ -run TestListBlockEventsScopesByAgent`
Expected: compile failure (fake signature) or `agentId` missing.

- [ ] **Step 3: Implement**

`sessions.go`: change the `BlockHistory` interface methods at 145-146 to take `agentID string` after `sessionID`; in `listBlockEvents` read `agentID := capActivityMeta(domain.SanitizeControlChars(strings.TrimSpace(r.URL.Query().Get("agentId"))))` and pass it to both calls.

`dto.go`: add to `BlockEventView` after `InteractionID`:

```go
	AgentID        string                  `json:"agentId,omitempty"`
	Detail         string                  `json:"detail,omitempty"`
```

and `AgentID: rec.AgentID, Detail: rec.Detail,` in `blockEventViews`. If `specgen/build.go` declares query parameters for `listSessionBlockEvents`, add `agentId` (string, optional, "Return only this subagent's events; empty means the main conversation").

Run `npm run api` from the repo root.

- [ ] **Step 4: Run the httpd suite**

Run: `cd backend && go test ./internal/httpd/...`
Expected: PASS, including spec drift tests.

- [ ] **Step 5: Full backend gate, then commit**

Run: `cd backend && go vet ./... && go test ./...`
Expected: PASS (a tmux integration test may flake once; rerun that package alone before deciding it is real).

```bash
git add backend/internal/httpd frontend/src/api/schema.ts
git commit -m "feat(api): agentId filter and view fields on session block events"
```

---

### Task 6: Mobile data layer and agent-scoped `BlocksCubit`

**Files:**
- Modify: `packages/mobile/lib/feature/blocks/data/model/block_event_model.dart`
- Modify: `packages/mobile/lib/feature/blocks/data/model/params/get_session_blocks_params.dart`
- Modify: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart:241-248`
- Modify: `packages/mobile/lib/core/app_routes/app_router.dart:113-119`
- Modify: `packages/mobile/lib/feature/sessions/presentation/session_route/ui/session_route_screen.dart:120-122`
- Create: `packages/mobile/lib/feature/blocks/logic/subagents.dart`
- Test: `packages/mobile/test/feature/blocks/data/block_event_model_test.dart`, `packages/mobile/test/feature/blocks/presentation/blocks_cubit_test.dart`, `packages/mobile/test/feature/blocks/logic/subagents_test.dart`

**Interfaces:**
- Produces: `BlockEventModel.agentId`, `BlockEventModel.detail` (String?); `GetSessionBlocksParams.agentId`; `class BlocksScope { final String sessionId; final String? harness; final String? agentId; }`; `BlocksCubit(MuxClient, BlocksRepository, BlocksScope scope)` with `String sessionId`, `String? agentId` getters; `Map<String, SubagentSummary> get subagentSummaries` on the main-scope cubit; `class SubagentSummary { final String agentId; final String? prompt; final String? startedAt; final String? lastSeenAt; final bool stopped; }`.

- [ ] **Step 1: Failing tests**

`block_event_model_test.dart`:

```dart
  test('reads agentId and detail off the wire', () {
    final model = BlockEventModel.fromJson({'seq': 1, 'kind': 'tool_result', 'agentId': 'a1', 'detail': '{"agentId":"a1"}'});
    expect(model.agentId, 'a1');
    expect(model.detail, '{"agentId":"a1"}');
  });
```

`blocks_cubit_test.dart`: change `build` to accept a scope and add:

```dart
  BlocksCubit build({String? harness = 'claude-code', String? agentId}) =>
      BlocksCubit(mux, repository, BlocksScope(sessionId: 's-1', harness: harness, agentId: agentId));

  test('an agent-scoped cubit keeps only its agent and asks history for it', () async {
    final cubit = build(agentId: 'a1');
    await Future<void>.delayed(Duration.zero);
    final captured = verify(() => repository.getSessionBlocks('s-1', captureAny())).captured.single as GetSessionBlocksParams;
    expect(captured.agentId, 'a1');

    events.add(BlockEventEnvelope('s-1', {..._wire(1, 'prompt_submit', text: 'main'), 'agentId': ''}));
    events.add(BlockEventEnvelope('s-1', {..._wire(2, 'prompt_submit', text: 'agent'), 'agentId': 'a1'}));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.blocks.single.body, 'agent');
    await cubit.close();
  });

  test('the main cubit ignores agent events but summarises them', () async {
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    events.add(BlockEventEnvelope('s-1', {..._wire(1, 'prompt_submit', text: 'Implement task 1'), 'agentId': 'a1', 'createdAt': '2026-09-19T10:00:00Z'}));
    events.add(BlockEventEnvelope('s-1', {..._wire(2, 'assistant_text', text: 'working'), 'agentId': 'a1', 'createdAt': '2026-09-19T10:00:05Z'}));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.blocks, isEmpty);
    final summary = cubit.subagentSummaries['a1']!;
    expect(summary.prompt, 'Implement task 1');
    expect(summary.startedAt, '2026-09-19T10:00:00Z');
    expect(summary.lastSeenAt, '2026-09-19T10:00:05Z');
    expect(summary.stopped, isFalse);

    events.add(BlockEventEnvelope('s-1', {..._wire(3, 'agent_stop'), 'agentId': 'a1'}));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.subagentSummaries['a1']!.stopped, isTrue);
    await cubit.close();
  });
```

`subagents_test.dart` (new):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/logic/subagents.dart';

SessionBlock _agent(String id, {String? agentId, String prompt = 'p', String status = 'running', BlockStatus blockStatus = BlockStatus.running}) => SessionBlock(
  id: id,
  firstSeq: 1,
  lastSeq: 1,
  kind: BlockKind.tool,
  status: blockStatus,
  title: 'Agent',
  body: '',
  toolName: 'Agent',
  createdAt: '2026-09-19T10:00:00Z',
  detail: AgentBlockDetail(description: 'Task $id', prompt: prompt, model: 'sonnet', agentId: agentId, status: status),
);

void main() {
  test('joins a tail to its card by agent id, else by prompt', () {
    final entries = subagentsOf(
      [_agent('c1', agentId: 'a1'), _agent('c2', prompt: 'Implement task 2')],
      {
        'a1': const SubagentSummary(agentId: 'a1', prompt: 'other', startedAt: '2026-09-19T10:00:00Z'),
        'a2': const SubagentSummary(agentId: 'a2', prompt: 'Implement task 2', startedAt: '2026-09-19T10:00:01Z'),
      },
    );
    expect(entries.map((e) => (e.card?.id, e.agentId)), [('c1', 'a1'), ('c2', 'a2')]);
  });

  test('a tail matching nothing is still listed under its agent id', () {
    final entries = subagentsOf(const [], {'zz': const SubagentSummary(agentId: 'zz', prompt: 'x')});
    expect(entries.single.agentId, 'zz');
    expect(entries.single.card, isNull);
    expect(entries.single.title, 'Agent');
  });

  test('running agents come first, then finished newest first', () {
    final entries = subagentsOf(
      [
        _agent('done-old', agentId: 'd1', status: 'completed', blockStatus: BlockStatus.ok),
        _agent('run', agentId: 'r1'),
        _agent('done-new', agentId: 'd2', status: 'completed', blockStatus: BlockStatus.ok),
      ],
      {
        'd1': const SubagentSummary(agentId: 'd1', lastSeenAt: '2026-09-19T10:01:00Z', stopped: true),
        'r1': const SubagentSummary(agentId: 'r1', lastSeenAt: '2026-09-19T10:02:00Z'),
        'd2': const SubagentSummary(agentId: 'd2', lastSeenAt: '2026-09-19T10:03:00Z', stopped: true),
      },
    );
    expect(entries.map((e) => e.agentId), ['r1', 'd2', 'd1']);
    expect(entries.first.running, isTrue);
  });
}
```

`AgentBlockDetail` is defined in Task 7; to keep this task compiling on its own, define it in this task (Step 3) and let Task 7 fill in the assembly.

- [ ] **Step 2: Run to verify failure**

Run: `cd packages/mobile && flutter test test/feature/blocks/data/block_event_model_test.dart test/feature/blocks/presentation/blocks_cubit_test.dart test/feature/blocks/logic/subagents_test.dart`
Expected: compile errors.

- [ ] **Step 3: Implement**

`block_event_model.dart`: add `final String? agentId; final String? detail;` to the class, constructor and `fromJson` (`agentId: json['agentId'] as String?, detail: json['detail'] as String?`), and to `props` if the model is `Equatable`.

`get_session_blocks_params.dart`: add `final String? agentId;`, constructor param, `if (agentId != null && agentId!.isNotEmpty) 'agentId': agentId,` in `toJson`, and props.

`session_block.dart`: add `agentId` to `SessionBlock` (constructor, field, `copyWith` passthrough as `agentId: agentId`, props) and the detail class:

```dart
class AgentBlockDetail extends BlockDetail {
  const AgentBlockDetail({
    this.description,
    this.prompt,
    this.model,
    this.runInBackground,
    this.agentId,
    this.agentType,
    this.status,
    this.resolvedModel,
    this.durationMs,
    this.toolUseCount,
    this.totalTokens,
  });

  final String? description;
  final String? prompt;
  final String? model;
  final bool? runInBackground;
  final String? agentId;
  final String? agentType;
  final String? status;
  final String? resolvedModel;
  final int? durationMs;
  final int? toolUseCount;
  final int? totalTokens;

  bool get finished => status == 'completed' || status == 'failed' || status == 'stopped';

  AgentBlockDetail merge(Map<String, dynamic> result) => AgentBlockDetail(
    description: description,
    prompt: prompt,
    model: model,
    runInBackground: runInBackground,
    agentId: result['agentId'] as String? ?? agentId,
    agentType: result['agentType'] as String? ?? agentType,
    status: result['status'] as String? ?? status,
    resolvedModel: result['resolvedModel'] as String? ?? resolvedModel,
    durationMs: (result['totalDurationMs'] as num?)?.toInt() ?? durationMs,
    toolUseCount: (result['totalToolUseCount'] as num?)?.toInt() ?? toolUseCount,
    totalTokens: (result['totalTokens'] as num?)?.toInt() ?? totalTokens,
  );

  static AgentBlockDetail? fromToolInput(String? toolInput) {
    if (toolInput == null || toolInput.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(toolInput);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    return AgentBlockDetail(
      description: decoded['description'] as String?,
      prompt: decoded['prompt'] as String?,
      model: decoded['model'] as String?,
      runInBackground: decoded['run_in_background'] as bool?,
      status: 'running',
    );
  }

  @override
  List<Object?> get props => [description, prompt, model, runInBackground, agentId, agentType, status, resolvedModel, durationMs, toolUseCount, totalTokens];
}
```

Add a `blockDisplay` arm: `AgentBlockDetail(:final description, :final agentType) => BlockDisplay(displayName: description ?? agentType ?? 'Agent', summary: block.body)`.

`subagents.dart` (new):

```dart
import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

class SubagentSummary extends Equatable {
  const SubagentSummary({required this.agentId, this.prompt, this.startedAt, this.lastSeenAt, this.stopped = false});

  final String agentId;
  final String? prompt;
  final String? startedAt;
  final String? lastSeenAt;
  final bool stopped;

  SubagentSummary absorb({String? prompt, String? at, bool stopped = false}) => SubagentSummary(
    agentId: agentId,
    prompt: this.prompt ?? prompt,
    startedAt: startedAt ?? at,
    lastSeenAt: at ?? lastSeenAt,
    stopped: this.stopped || stopped,
  );

  @override
  List<Object?> get props => [agentId, prompt, startedAt, lastSeenAt, stopped];
}

class SubagentEntry extends Equatable {
  const SubagentEntry({required this.agentId, this.card, this.summary});

  final String? agentId;
  final SessionBlock? card;
  final SubagentSummary? summary;

  AgentBlockDetail? get detail => card?.detail is AgentBlockDetail ? card!.detail! as AgentBlockDetail : null;
  String get title => detail?.description ?? detail?.agentType ?? 'Agent';
  bool get running => !(summary?.stopped ?? false) && !(detail?.finished ?? false) && card?.status != BlockStatus.ok && card?.status != BlockStatus.failed;
  String? get startedAt => card?.createdAt ?? summary?.startedAt;
  String? get lastSeenAt => summary?.lastSeenAt ?? card?.createdAt;

  @override
  List<Object?> get props => [agentId, card, summary];
}

List<SubagentEntry> subagentsOf(List<SessionBlock> mainBlocks, Map<String, SubagentSummary> tails) {
  final unclaimed = Map<String, SubagentSummary>.of(tails);
  final entries = <SubagentEntry>[];
  for (final block in _flatten(mainBlocks)) {
    final detail = block.detail;
    if (detail is! AgentBlockDetail) continue;
    SubagentSummary? match;
    if (detail.agentId != null) {
      match = unclaimed.remove(detail.agentId);
    } else {
      final byPrompt = unclaimed.values.where((s) => s.prompt != null && s.prompt == detail.prompt).firstOrNull;
      if (byPrompt != null) match = unclaimed.remove(byPrompt.agentId);
    }
    entries.add(SubagentEntry(agentId: detail.agentId ?? match?.agentId, card: block, summary: match));
  }
  for (final summary in unclaimed.values) {
    entries.add(SubagentEntry(agentId: summary.agentId, summary: summary));
  }
  entries.sort((a, b) {
    if (a.running != b.running) return a.running ? -1 : 1;
    if (a.running) return (a.startedAt ?? '').compareTo(b.startedAt ?? '');
    return (b.lastSeenAt ?? '').compareTo(a.lastSeenAt ?? '');
  });
  return entries;
}

Iterable<SessionBlock> _flatten(List<SessionBlock> blocks) sync* {
  for (final block in blocks) {
    yield block;
    if (block.children != null) yield* _flatten(block.children!);
  }
}
```

`blocks_cubit.dart`: add

```dart
class BlocksScope extends Equatable {
  const BlocksScope({required this.sessionId, this.harness, this.agentId});

  final String sessionId;
  final String? harness;
  final String? agentId;

  @override
  List<Object?> get props => [sessionId, harness, agentId];
}
```

Change the constructor to `BlocksCubit(this._mux, this._repository, this.scope)` with `final BlocksScope scope; String get sessionId => scope.sessionId; String? get agentId => scope.agentId; String? get harness => scope.harness;` (keep `supported = BlockHarnesses.covers(scope.harness)`). Replace the live filter with:

```dart
    _eventsSub = _mux.blockEvents.where((event) => event.sessionId == sessionId).listen(_onLive);
```

and in `_onLive`:

```dart
  void _onLive(BlockEventEnvelope envelope) {
    final record = BlockEventModel.fromJson(envelope.block);
    final scopeId = record.agentId ?? '';
    if (scopeId == (agentId ?? '')) {
      _merge(record);
      _rebuild();
      return;
    }
    if (agentId == null && scopeId.isNotEmpty) _summarise(scopeId, record);
  }

  final Map<String, SubagentSummary> _summaries = {};
  Map<String, SubagentSummary> get subagentSummaries => Map.unmodifiable(_summaries);

  void _summarise(String scopeId, BlockEventModel record) {
    final current = _summaries[scopeId] ?? SubagentSummary(agentId: scopeId);
    _summaries[scopeId] = current.absorb(
      prompt: record.kind == 'prompt_submit' ? record.text : null,
      at: record.createdAt,
      stopped: record.kind == 'agent_stop',
    );
    _emit();
  }
```

Pass `agentId: agentId` in both `GetSessionBlocksParams` constructions. Import `subagents.dart`.

`service_locator.dart`: change the registration to

```dart
    sl.registerFactoryParam<BlocksCubit, BlocksScope, void>(
      (scope, _) => BlocksCubit(sl<MuxClient>(), sl<BlocksRepository>(), scope),
    );
```

`app_router.dart:113-119` and `session_route_screen.dart:120-122`: replace `sl<BlocksCubit>(param1: ..., param2: ...)` with `sl<BlocksCubit>(param1: BlocksScope(sessionId: terminalArgs.sessionId, harness: terminalArgs.harness))` (and `args.sessionId` / `args.harness` in the route screen). Fix every other `BlocksCubit(` construction `flutter analyze` reports (tests included) to the new signature.

- [ ] **Step 4: Run the gate**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: `No issues found!`, all tests pass.

- [ ] **Step 5: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): agent-scoped block events, AgentBlockDetail and subagent summaries"
```

---

### Task 7: Assembly builds the Agent detail and honours `agent_stop`

**Files:**
- Modify: `packages/mobile/lib/feature/blocks/logic/block_assembly.dart`
- Test: `packages/mobile/test/feature/blocks/logic/block_assembly_test.dart`

**Interfaces:**
- Consumes: `AgentBlockDetail.fromToolInput`, `AgentBlockDetail.merge` (Task 6); `BlockEventModel.detail`, `agentId`.
- Produces: Agent tool blocks carry `AgentBlockDetail`; `SessionBlock.agentId` mirrors the event.

- [ ] **Step 1: Failing tests**

Extend the `_event` helper in `block_assembly_test.dart` with `String? detail, String? agentId` passed through to `BlockEventModel`, then add a group:

```dart
  group('agents', () {
    const input = '{"description":"Implement Task 1","prompt":"You are implementing Task 1","model":"haiku","run_in_background":true}';

    test('an Agent tool block carries its description, prompt and model', () {
      final blocks = assembleBlocks([
        _event(1, 'tool_start', sourceId: 'toolu_a', toolUseId: 'toolu_a', toolName: 'Agent', source: 'transcript', toolInput: input),
      ]);
      final detail = blocks.single.detail as AgentBlockDetail;
      expect(detail.description, 'Implement Task 1');
      expect(detail.prompt, 'You are implementing Task 1');
      expect(detail.model, 'haiku');
      expect(detail.status, 'running');
      expect(blocks.single.status, BlockStatus.running);
    });

    test('the Agent result merges the agent identity and totals', () {
      final blocks = assembleBlocks([
        _event(1, 'tool_start', sourceId: 'toolu_a', toolUseId: 'toolu_a', toolName: 'Agent', source: 'transcript', toolInput: input),
        _event(2, 'tool_result', sourceId: 'toolu_a', toolUseId: 'toolu_a', source: 'transcript', text: 'done',
            detail: '{"agentId":"a1","agentType":"general-purpose","status":"completed","resolvedModel":"claude-haiku-4-5","totalDurationMs":61000,"totalToolUseCount":7,"totalTokens":9000}'),
      ]);
      final detail = blocks.single.detail as AgentBlockDetail;
      expect(detail.agentId, 'a1');
      expect(detail.agentType, 'general-purpose');
      expect(detail.status, 'completed');
      expect(detail.durationMs, 61000);
      expect(detail.toolUseCount, 7);
      expect(detail.description, 'Implement Task 1');
      expect(blocks.single.status, BlockStatus.ok);
    });

    test('an agent_stop completes the Agent block it names', () {
      final blocks = assembleBlocks([
        _event(1, 'tool_start', sourceId: 'toolu_a', toolUseId: 'toolu_a', toolName: 'Agent', source: 'transcript', toolInput: input),
        _event(2, 'tool_result', sourceId: 'toolu_a', toolUseId: 'toolu_a', source: 'transcript', text: 'Async agent launched',
            detail: '{"agentId":"a1","agentType":"general-purpose","status":"running"}'),
        _event(3, 'agent_stop', sourceId: 'a1', agentId: 'a1', source: 'hook', text: 'finished'),
      ]);
      final detail = blocks.single.detail as AgentBlockDetail;
      expect(detail.status, 'completed');
    });

    test('agent-scoped events carry the agent id onto their blocks', () {
      final blocks = assembleBlocks([_event(1, 'prompt_submit', text: 'go', agentId: 'a1')]);
      expect(blocks.single.agentId, 'a1');
    });
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `cd packages/mobile && flutter test test/feature/blocks/logic/block_assembly_test.dart`
Expected: FAIL (detail is `UnknownBlockDetail`; `agent_stop` renders as a notice).

- [ ] **Step 3: Implement**

In `block_assembly.dart`:

- In `_create`, replace the `detail:` line with
  `detail: detail ?? (event.toolName == 'Agent' ? AgentBlockDetail.fromToolInput(event.toolInput) : null) ?? UnknownBlockDetail(raw: event.toolInput ?? event.text ?? ''),` and add `agentId: (event.agentId ?? '').isEmpty ? null : event.agentId,`.
- In `tool_start`'s `at != null` branch, when `blocks[at].detail is! AgentBlockDetail && event.toolName == 'Agent'`, pass `detail: AgentBlockDetail.fromToolInput(body)` in the `copyWith`.
- In `tool_result`'s `at != null` branch, before the `copyWith`, compute
  ```dart
  final agentDetail = target.detail is AgentBlockDetail && (event.detail ?? '').isNotEmpty
      ? (target.detail! as AgentBlockDetail).merge(_decodeMap(event.detail!))
      : null;
  ```
  and pass `detail: agentDetail` to that `copyWith`.
- Add a case:
  ```dart
      case 'agent_stop':
        final stopped = event.agentId ?? '';
        if (stopped.isEmpty) continue;
        for (var i = 0; i < blocks.length; i++) {
          final detail = blocks[i].detail;
          if (detail is AgentBlockDetail && detail.agentId == stopped && !detail.finished) {
            blocks[i] = blocks[i].copyWith(detail: detail.merge(const {'status': 'completed'}), lastSeq: seq);
          }
        }
  ```
  placed before `case 'unknown':`, and add `'agent_stop'` to `_correlatingKinds`.
- Add the helper:
  ```dart
  Map<String, dynamic> _decodeMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }
  ```
  with `import 'dart:convert';`.

- [ ] **Step 4: Run the gate**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add packages/mobile/lib/feature/blocks/logic/block_assembly.dart packages/mobile/test/feature/blocks/logic/block_assembly_test.dart
git commit -m "feat(mobile): assemble Agent tool blocks with their agent detail and agent_stop"
```

---

### Task 8: Agent card in the timeline

**Files:**
- Modify: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart:29-70, 85-92, 200-215, 365-380`
- Modify: `packages/mobile/lib/core/app_routes/routes_strings.dart`
- Test: `packages/mobile/test/feature/blocks/presentation/blocks_screen/block_card_test.dart`

**Interfaces:**
- Produces: `RailKind.agent`; `RoutesStrings.subagent = '/session/agent'`; tapping the card calls `Navigator.of(context).pushNamed(RoutesStrings.subagent, arguments: {'sessionId': ..., 'agentId': ..., 'detail': AgentBlockDetail, 'parentTitle': String?})`; `BlockCard.onOpenAgent` optional callback `void Function(SessionBlock block)?` used by tests and by `BlockList` (Task 9 wires the navigation; the default handler pushes the route itself).

- [ ] **Step 1: Failing widget test**

In `block_card_test.dart` add (reuse the file's `_card` pump helper; it already provides `SkinScope` and an optional `SessionCommandCubit`):

```dart
  SessionBlock _agentBlock({String status = 'running', BlockStatus blockStatus = BlockStatus.running}) => SessionBlock(
    id: 'src-toolu_a',
    firstSeq: 1,
    lastSeq: 1,
    kind: BlockKind.tool,
    status: blockStatus,
    title: 'Agent',
    body: '',
    toolName: 'Agent',
    createdAt: DateTime.now().toUtc().subtract(const Duration(seconds: 75)).toIso8601String(),
    detail: AgentBlockDetail(description: 'Implement Task 1', prompt: 'p', model: 'haiku', agentType: 'general-purpose', agentId: 'a1', status: status, toolUseCount: 7, durationMs: 362000),
  );

  testWidgets('a running agent card shows its description, type, model and live elapsed time', (tester) async {
    await tester.pumpWidget(_card(_agentBlock()));
    expect(find.text('Implement Task 1'), findsOneWidget);
    expect(find.textContaining('general-purpose'), findsOneWidget);
    expect(find.textContaining('haiku'), findsOneWidget);
    expect(find.textContaining('1m15s'), findsOneWidget);
  });

  testWidgets('a finished agent card shows duration and tool count and no timer', (tester) async {
    await tester.pumpWidget(_card(_agentBlock(status: 'completed', blockStatus: BlockStatus.ok)));
    expect(find.textContaining('6m02s'), findsOneWidget);
    expect(find.textContaining('7 tools'), findsOneWidget);
  });

  testWidgets('tapping an agent card reports the block to open', (tester) async {
    SessionBlock? opened;
    await tester.pumpWidget(_card(_agentBlock(), onOpenAgent: (block) => opened = block));
    await tester.tap(find.text('Implement Task 1'));
    expect(opened?.id, 'src-toolu_a');
  });
```

Extend the file's `_card` helper with an `onOpenAgent` parameter passed to `BlockCard`.

- [ ] **Step 2: Run to verify failure**

Run: `cd packages/mobile && flutter test test/feature/blocks/presentation/blocks_screen/block_card_test.dart`
Expected: FAIL (no `onOpenAgent`, plain tool rendering).

- [ ] **Step 3: Implement**

`routes_strings.dart`: add `static const String subagent = '/session/agent';`.

`block_card.dart`:

- `enum RailKind` gains `agent`. In `railKindOf`, inside `case BlockKind.tool:` before the MCP check: `if (block.detail is AgentBlockDetail) return RailKind.agent;`.
- `railNodeColor`: `RailKind.agent => blockStatusColor(skin, block.status)`.
- `BlockCard` gains `this.onOpenAgent` (`final void Function(SessionBlock block)? onOpenAgent;`), passed into `_RailBody` as `onOpenAgent`.
- In `BlockCard.build`'s `core` switch, treat `RailKind.agent` like `RailKind.group` (same padding) so it sits inside tool groups.
- In `_RailBody.build` add `case RailKind.agent: return _AgentBody(block: block, collapsed: collapsed, onLongPress: onLongPressHeader ?? onLongPressBody, onOpen: () => _openAgent(context));` where

```dart
  void _openAgent(BuildContext context) {
    if (onOpenAgent != null) {
      onOpenAgent!(block);
      return;
    }
    final detail = block.detail! as AgentBlockDetail;
    Navigator.of(context).pushNamed(
      RoutesStrings.subagent,
      arguments: {
        'sessionId': context.read<BlocksCubit>().sessionId,
        'agentId': detail.agentId,
        'detail': detail,
      },
    );
  }
```

(import `blocks_cubit.dart` and `routes_strings.dart`). When `detail.agentId` is null and no summary link exists yet, the route opens with a null agent id; Task 9's screen shows "Waiting for the agent's transcript" in that case.

- Add the body widget:

```dart
class _AgentBody extends StatefulWidget {
  const _AgentBody({required this.block, required this.collapsed, required this.onLongPress, required this.onOpen});

  final SessionBlock block;
  final bool collapsed;
  final VoidCallback onLongPress;
  final VoidCallback onOpen;

  @override
  State<_AgentBody> createState() => _AgentBodyState();
}

class _AgentBodyState extends State<_AgentBody> {
  Timer? _timer;

  AgentBlockDetail get _detail => widget.block.detail! as AgentBlockDetail;

  bool get _running => !_detail.finished && widget.block.status == BlockStatus.running;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _running) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _meta {
    if (_running) {
      final start = DateTime.tryParse(widget.block.createdAt ?? '');
      final elapsed = start == null ? '' : formatDuration(DateTime.now().toUtc().difference(start.toUtc()));
      final tools = _detail.toolUseCount;
      return ['running', if (elapsed.isNotEmpty) elapsed, if (tools != null) '$tools tools'].join(' · ');
    }
    final duration = _detail.durationMs == null ? null : formatDuration(Duration(milliseconds: _detail.durationMs!));
    final tools = _detail.toolUseCount;
    final state = widget.block.status == BlockStatus.failed || _detail.status == 'failed' ? 'failed' : 'done';
    return [state, if (duration != null) duration, if (tools != null) '$tools tools'].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final subtitle = [_detail.agentType, _detail.resolvedModel ?? _detail.model].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onOpen,
      onLongPress: widget.onLongPress,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            BlockStatusDot(status: widget.block.status),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(_detail.description ?? _detail.agentType ?? 'Agent', style: AppTextStyle.style12Medium.copyWith(color: skin.textPrimary)),
                  if (subtitle.isNotEmpty) AppText(subtitle, style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AppText(_meta, style: AppTextStyle.mono11Regular.copyWith(color: widget.block.status == BlockStatus.failed ? skin.red : skin.textTertiary)),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 16, color: skin.textTertiary),
          ],
        ),
      ),
    );
  }
}

String formatDuration(Duration d) {
  final seconds = d.inSeconds.clamp(0, 1 << 31);
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  if (minutes < 60) return '${minutes}m${rest.toString().padLeft(2, '0')}s';
  return '${minutes ~/ 60}h${(minutes % 60).toString().padLeft(2, '0')}m';
}
```

Import `dart:async`. Group compact rows: in `_GroupBody`'s header, `display.displayName` already resolves to the description through the `blockDisplay` arm added in Task 6, so "Agent" rows inside a collapsed group show the description.

- [ ] **Step 4: Run the gate**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: pass. If the 1m15s assertion is flaky by a second, build the block with `createdAt` 75 s ago right before pumping and accept `1m1[4-6]s` with a `RegExp` in `find.textContaining`.

- [ ] **Step 5: Commit**

```bash
git add packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart packages/mobile/lib/core/app_routes/routes_strings.dart packages/mobile/test/feature/blocks/presentation/blocks_screen/block_card_test.dart
git commit -m "feat(mobile): agent card with live elapsed time that opens the subagent"
```

---

### Task 9: Subagent screen and route

**Files:**
- Create: `packages/mobile/lib/feature/blocks/presentation/subagent_screen/ui/subagent_screen.dart`
- Modify: `packages/mobile/lib/core/app_routes/app_router.dart` (new case)
- Modify: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart:800-870` (`_PermissionBody` copy when the block is agent-scoped)
- Test: `packages/mobile/test/feature/blocks/presentation/subagent_screen_test.dart`

**Interfaces:**
- Consumes: `BlocksCubit(BlocksScope(sessionId, harness, agentId))`, `SessionCommandCubit` (existing DI), `BlocksBody`, `GlobalAppbar.sub`.
- Produces: `SubagentScreen({required String sessionId, required String? agentId, required AgentBlockDetail? detail, String? parentTitle})`.

- [ ] **Step 1: Failing widget test**

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/subagent_screen/ui/subagent_screen.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart';

class _MockBlocksCubit extends MockCubit<BlocksState> implements BlocksCubit {}

class _MockCommandCubit extends MockCubit<SessionCommandState> implements SessionCommandCubit {}

void main() {
  testWidgets('shows the agent title, breadcrumb and no composer', (tester) async {
    final blocks = _MockBlocksCubit();
    when(() => blocks.state).thenReturn(const BlocksReadyState(1));
    when(() => blocks.sessionId).thenReturn('s-1');
    when(() => blocks.agentId).thenReturn('a1');
    when(() => blocks.supported).thenReturn(true);
    when(() => blocks.harness).thenReturn('claude-code');
    when(() => blocks.blocks).thenReturn([
      SessionBlock(id: 'seq-1', firstSeq: 1, lastSeq: 1, kind: BlockKind.prompt, status: BlockStatus.ok, title: 'Prompt', body: 'Implement task 1', agentId: 'a1'),
      SessionBlock(id: 'seq-2', firstSeq: 2, lastSeq: 2, kind: BlockKind.permission, status: BlockStatus.blocked, title: 'Permission requested', body: 'Bash\nls', agentId: 'a1', interactionId: 'i1'),
    ]);
    when(() => blocks.loading).thenReturn(false);
    when(() => blocks.active).thenReturn(true);
    when(() => blocks.loadingOlder).thenReturn(false);
    when(() => blocks.hasOlder).thenReturn(false);
    when(() => blocks.error).thenReturn(null);
    when(() => blocks.refresh()).thenAnswer((_) async {});
    when(() => blocks.loadOlder()).thenAnswer((_) async {});
    final commands = _MockCommandCubit();
    when(() => commands.state).thenReturn(const SessionCommandState());

    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<BlocksCubit>.value(value: blocks),
                BlocProvider<SessionCommandCubit>.value(value: commands),
              ],
              child: const SubagentScreen(
                sessionId: 's-1',
                agentId: 'a1',
                parentTitle: 'Impl Plan A',
                detail: AgentBlockDetail(description: 'Implement Task 1', agentType: 'general-purpose', model: 'haiku', status: 'running'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Implement Task 1'), findsOneWidget);
    expect(find.textContaining('Impl Plan A'), findsOneWidget);
    expect(find.textContaining('general-purpose'), findsOneWidget);
    expect(find.byType(TerminalComposer), findsNothing);
    expect(find.text('Answer in the parent session'), findsOneWidget);
    expect(find.text('Allow once'), findsNothing);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd packages/mobile && flutter test test/feature/blocks/presentation/subagent_screen_test.dart`
Expected: compile error (no `SubagentScreen`).

- [ ] **Step 3: Implement**

`subagent_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart';

class SubagentScreen extends StatelessWidget {
  const SubagentScreen({super.key, required this.sessionId, required this.agentId, required this.detail, this.parentTitle});

  final String sessionId;
  final String? agentId;
  final AgentBlockDetail? detail;
  final String? parentTitle;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final title = detail?.description ?? detail?.agentType ?? 'Agent';
    final subtitle = [detail?.agentType, detail?.resolvedModel ?? detail?.model, detail?.status]
        .whereType<String>()
        .where((part) => part.isNotEmpty)
        .join(' · ');
    return Scaffold(
      backgroundColor: skin.bgBase,
      appBar: GlobalAppbar.sub(
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (parentTitle != null)
              AppText('↩ $parentTitle', style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary)),
            AppText(title, style: AppTextStyle.style15SemiBold.copyWith(color: skin.textPrimary)),
            if (subtitle.isNotEmpty) AppText(subtitle, style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary)),
          ],
        ),
      ),
      body: agentId == null
          ? Center(
              child: AppText("Waiting for the agent's transcript", style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary)),
            )
          : BlocBuilder<BlocksCubit, BlocksState>(builder: (context, _) => const BlocksBody()),
    );
  }
}
```

Use whichever `AppTextStyle` sizes the session header uses for its title if `style15SemiBold` does not exist (check `terminal_chat_header.dart`).

`app_router.dart`, new case before `RoutesStrings.preview`:

```dart
      case RoutesStrings.subagent:
        final args = settings.arguments as Map<String, dynamic>? ?? const {};
        final sessionId = args['sessionId'] as String? ?? '';
        final agentId = args['agentId'] as String?;
        final detail = args['detail'] as AgentBlockDetail?;
        return MaterialPageRoute(
          builder: (context) => MultiBlocProvider(
            providers: [
              BlocProvider<BlocksCubit>(
                create: (_) => sl<BlocksCubit>(param1: BlocksScope(sessionId: sessionId, harness: 'claude-code', agentId: agentId)),
              ),
              BlocProvider<SessionCommandCubit>(create: (_) => sl<SessionCommandCubit>(param1: sessionId, param2: null)),
            ],
            child: SubagentScreen(sessionId: sessionId, agentId: agentId, detail: detail, parentTitle: args['parentTitle'] as String?),
          ),
          settings: settings,
        );
```

Pass `'harness': context.read<BlocksCubit>().harness` from the card's `_openAgent` (Task 8) and use `args['harness'] as String? ?? 'claude-code'` here instead of the literal.

`block_card.dart` `_PermissionBody`: change the final `if/else if/else` so that when `block.agentId != null` the body shows `AppText('Answer in the parent session', style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary))` regardless of `interactionId`; the same for `_QuestionBody` (render `BlockQuestionOptions` disabled or replace with the same line). The blocked status still drives the amber dot.

- [ ] **Step 4: Run the gate**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add packages/mobile/lib/feature/blocks/presentation/subagent_screen packages/mobile/lib/core/app_routes/app_router.dart packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart packages/mobile/test/feature/blocks/presentation/subagent_screen_test.dart
git commit -m "feat(mobile): read-only subagent screen behind /session/agent"
```

---

### Task 10: Subagent strip above the composer

**Files:**
- Create: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/subagent_strip.dart`
- Modify: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_body.dart:100-118`
- Test: `packages/mobile/test/feature/blocks/presentation/blocks_screen/subagent_strip_test.dart`

**Interfaces:**
- Consumes: `subagentsOf`, `SubagentEntry`, `BlocksCubit.blocks`, `BlocksCubit.subagentSummaries`, `formatDuration` (Task 8), `RoutesStrings.subagent`.
- Produces: `SubagentStrip({void Function(SubagentEntry entry)? onOpen})`; it renders `SizedBox.shrink()` when there are no entries.

- [ ] **Step 1: Failing widget test**

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/logic/subagents.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/subagent_strip.dart';

class _MockBlocksCubit extends MockCubit<BlocksState> implements BlocksCubit {}

SessionBlock _agent(String id, String agentId, {bool running = true}) => SessionBlock(
  id: id,
  firstSeq: 1,
  lastSeq: 1,
  kind: BlockKind.tool,
  status: running ? BlockStatus.running : BlockStatus.ok,
  title: 'Agent',
  body: '',
  toolName: 'Agent',
  createdAt: '2026-09-19T10:00:00Z',
  detail: AgentBlockDetail(description: 'Task $id', agentId: agentId, status: running ? 'running' : 'completed', durationMs: 5000, toolUseCount: 3),
);

Future<void> _pump(WidgetTester tester, _MockBlocksCubit cubit, {void Function(SubagentEntry)? onOpen}) => tester.pumpWidget(
  SkinScope(
    skin: const DarkSkin(),
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, _) => MaterialApp(
        home: Scaffold(body: BlocProvider<BlocksCubit>.value(value: cubit, child: SubagentStrip(onOpen: onOpen))),
      ),
    ),
  ),
);

void main() {
  late _MockBlocksCubit cubit;

  setUp(() {
    cubit = _MockBlocksCubit();
    when(() => cubit.state).thenReturn(const BlocksReadyState(1));
    when(() => cubit.subagentSummaries).thenReturn(const {});
  });

  testWidgets('renders nothing without agents', (tester) async {
    when(() => cubit.blocks).thenReturn(const []);
    await _pump(tester, cubit);
    expect(find.byType(SizedBox), findsOneWidget);
    expect(find.textContaining('done'), findsNothing);
  });

  testWidgets('lists running agents and folds finished ones into a count', (tester) async {
    when(() => cubit.blocks).thenReturn([_agent('1', 'a1'), _agent('2', 'a2', running: false), _agent('3', 'a3', running: false)]);
    SubagentEntry? opened;
    await _pump(tester, cubit, onOpen: (entry) => opened = entry);

    expect(find.text('Task 1'), findsOneWidget);
    expect(find.text('2 done'), findsOneWidget);
    expect(find.text('Task 2'), findsNothing);

    await tester.tap(find.text('Task 1'));
    expect(opened?.agentId, 'a1');

    await tester.tap(find.text('2 done'));
    await tester.pumpAndSettle();
    expect(find.text('Task 2'), findsOneWidget);
    expect(find.text('Task 3'), findsOneWidget);
    await tester.tap(find.text('Task 3'));
    await tester.pumpAndSettle();
    expect(opened?.agentId, 'a3');
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd packages/mobile && flutter test test/feature/blocks/presentation/blocks_screen/subagent_strip_test.dart`
Expected: compile error (no `SubagentStrip`).

- [ ] **Step 3: Implement**

`subagent_strip.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/logic/subagents.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_status_dot.dart';

class SubagentStrip extends StatefulWidget {
  const SubagentStrip({super.key, this.onOpen, this.parentTitle});

  final void Function(SubagentEntry entry)? onOpen;
  final String? parentTitle;

  @override
  State<SubagentStrip> createState() => _SubagentStripState();
}

class _SubagentStripState extends State<SubagentStrip> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _open(BuildContext context, SubagentEntry entry) {
    if (widget.onOpen != null) {
      widget.onOpen!(entry);
      return;
    }
    final cubit = context.read<BlocksCubit>();
    Navigator.of(context).pushNamed(
      RoutesStrings.subagent,
      arguments: {
        'sessionId': cubit.sessionId,
        'agentId': entry.agentId,
        'detail': entry.detail,
        'harness': cubit.harness,
        'parentTitle': widget.parentTitle,
      },
    );
  }

  void _showFinished(BuildContext context, List<SubagentEntry> finished) {
    final skin = context.skin;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: skin.bgElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppConstants.radiusLg))),
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final entry in finished)
              ListTile(
                dense: true,
                leading: BlockStatusDot(status: entry.card?.status ?? BlockStatus.ok),
                title: AppText(entry.title, style: AppTextStyle.style12Medium.copyWith(color: skin.textPrimary)),
                subtitle: AppText(_finishedMeta(entry), style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary)),
                trailing: Icon(Icons.chevron_right, size: 16, color: skin.textTertiary),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _open(context, entry);
                },
              ),
          ],
        ),
      ),
    );
  }

  String _finishedMeta(SubagentEntry entry) {
    final detail = entry.detail;
    return [
      detail?.agentType,
      if (detail?.durationMs != null) formatDuration(Duration(milliseconds: detail!.durationMs!)),
      if (detail?.toolUseCount != null) '${detail!.toolUseCount} tools',
    ].whereType<String>().join(' · ');
  }

  String _runningMeta(SubagentEntry entry) {
    final start = DateTime.tryParse(entry.startedAt ?? '');
    return start == null ? '' : formatDuration(DateTime.now().toUtc().difference(start.toUtc()));
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<BlocksCubit, BlocksState>(
    builder: (context, _) {
      final cubit = context.read<BlocksCubit>();
      final entries = subagentsOf(cubit.blocks, cubit.subagentSummaries);
      if (entries.isEmpty) return const SizedBox.shrink();
      final skin = context.skin;
      final running = entries.where((e) => e.running).toList();
      final finished = entries.where((e) => !e.running).toList();
      return Container(
        height: 44,
        decoration: BoxDecoration(color: skin.bgChrome, border: Border(top: BorderSide(color: skin.borderSubtle))),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          children: [
            for (final entry in running) ...[
              _Pill(
                dot: BlockStatusDot(status: BlockStatus.running),
                label: entry.title,
                meta: _runningMeta(entry),
                onTap: () => _open(context, entry),
              ),
              const SizedBox(width: 8),
            ],
            if (finished.isNotEmpty)
              _Pill(
                dot: null,
                label: '${finished.length} done',
                meta: '',
                failed: finished.any((e) => e.card?.status == BlockStatus.failed),
                onTap: () => _showFinished(context, finished),
              ),
          ],
        ),
      );
    },
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.dot, required this.label, required this.meta, required this.onTap, this.failed = false});

  final Widget? dot;
  final String label;
  final String meta;
  final VoidCallback onTap;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final shown = label.length > 22 ? '${label.substring(0, 22)}…' : label;
    return Material(
      color: failed ? skin.tintRed : skin.bgElevated,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[dot!, const SizedBox(width: 6)],
              AppText(shown, style: AppTextStyle.style12Medium.copyWith(color: failed ? skin.red : skin.textSecondary)),
              if (meta.isNotEmpty) ...[
                const SizedBox(width: 6),
                AppText(meta, style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

The first test expects exactly one `SizedBox` in the empty case; `SizedBox.shrink()` at the strip root satisfies that because the test scaffold adds none of its own. If the `MaterialApp` scaffold contributes `SizedBox`es, change the assertion to `find.byType(ListView), findsNothing`.

`terminal_body.dart`: inside the bottom `Container`'s `Column`, before `if (!blocksMode) const TerminalKeyRow(),` add `if (blocksMode) SubagentStrip(parentTitle: cubit.args.title),`. The strip is built only in blocks mode, so a shell-only pane (no `BlocksCubit`) never reaches it; guard anyway with `if (blocksMode && !cubit.args.shellOnly)`.

- [ ] **Step 4: Run the gate**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/subagent_strip.dart packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_body.dart packages/mobile/test/feature/blocks/presentation/blocks_screen/subagent_strip_test.dart
git commit -m "feat(mobile): subagent strip above the composer with a finished-agents sheet"
```

---

### Task 11: Real-app verification and docs

**Files:**
- Modify: `CLAUDE.md` (mobile architecture section: one sentence on the `blocks` feature's agent scope), `docs/mobile-parity-ledger.md` only if it has a "not ported" entry for subagents.

- [ ] **Step 1: Rebuild and run the daemon against a session that dispatches agents**

Follow `RUN_APP_COMMANDS.md` to rebuild the daemon and start `tauri:dev` with the scrubbed `CLAUDE*` environment (see `RUN_APP_COMMANDS.md` and the memory note on scrubbing). Start a Claude Code session and ask it to dispatch two background subagents (for example "spawn two Agent tool calls with `run_in_background: true` that each list the repo root").

- [ ] **Step 2: Check the daemon side with the API**

```bash
curl -s -H "Authorization: Bearer $OPR_TOKEN" 'http://127.0.0.1:3002/api/v1/sessions/<id>/blocks' | jq '[.blocks[] | select(.agentId != null)] | length'
curl -s -H "Authorization: Bearer $OPR_TOKEN" 'http://127.0.0.1:3002/api/v1/sessions/<id>/blocks?agentId=<agentId>' | jq '.blocks | map(.kind)'
```

Expected: the first command prints `0` (main stream stays clean); the second prints a list starting with `prompt_submit` followed by `turn_model`, `assistant_text`, `tool_start`, `tool_result`, …

- [ ] **Step 3: Check the phone**

Pair the phone to the rebuilt daemon (or run the Flutter app on the simulator against it). Confirm: the two Agent cards show description, type, model and a ticking elapsed time; the strip appears with both pills; tapping a pill opens the agent's conversation with the breadcrumb showing the parent title; back returns to the parent at the same scroll position; when both finish the strip shows `2 done`, the sheet lists both with durations, and each opens.

- [ ] **Step 4: Docs**

In `CLAUDE.md`'s mobile Architecture section add, after the `MuxClient` paragraph: "Block events carry an optional `agentId`. `BlocksCubit` is scoped by `BlocksScope`; the main scope also collects `SubagentSummary` per agent from the events it discards, and `subagentsOf` joins those to Agent cards for the strip and the `/session/agent` screen."

- [ ] **Step 5: Final gates and commit**

Run: `cd backend && go vet ./... && go test ./...` and `cd packages/mobile && flutter analyze && flutter test`.

```bash
git add CLAUDE.md docs/mobile-parity-ledger.md
git commit -m "docs: mobile subagent scope in the architecture notes"
```
