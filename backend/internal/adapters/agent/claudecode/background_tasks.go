package claudecode

import (
	"encoding/json"
	"html"
	"regexp"
	"slices"
	"strconv"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

const (
	maxRememberedLaunches = 512
	maxRememberedFinished = 256
)

type taskLaunch struct {
	name        string
	description string
	command     string
	timestamp   string
}

type knownTask struct {
	task domain.BackgroundTask
	tool string
}

type TranscriptMapper struct {
	agentID  string
	launches map[string]taskLaunch
	order    []string
	tasks    map[string]knownTask
	seen     map[string]struct{}
	finished []string
}

func NewTranscriptMapper(agentID string) *TranscriptMapper {
	return &TranscriptMapper{
		agentID:  agentID,
		launches: map[string]taskLaunch{},
		tasks:    map[string]knownTask{},
		seen:     map[string]struct{}{},
	}
}

func (m *TranscriptMapper) Map(line []byte) ([]domain.BlockTranscriptEvent, bool) {
	var rec claudeTranscriptRecord
	if err := json.Unmarshal(line, &rec); err != nil {
		return nil, false
	}
	sidechain := m.agentID != ""
	if rec.IsSidechain && !sidechain {
		return nil, true
	}
	var events []domain.BlockTranscriptEvent
	known := true
	if rec.Type == "queue-operation" {
		if rec.Operation == "enqueue" {
			events = m.notificationEvents(claudeFlattenText(rec.Content), rec.Timestamp)
		}
	} else {
		events, known = mapClaudeRecord(rec, sidechain)
		switch rec.Type {
		case "assistant":
			m.rememberLaunches(rec)
		case "user":
			events = append(events, m.launchEvents(rec)...)
			if rec.Origin.Kind == "task-notification" {
				events = append(events, m.notificationEvents(claudeFlattenText(rec.Message.Content), rec.Timestamp)...)
			}
		}
	}
	if sidechain {
		for i := range events {
			events[i].AgentID = m.agentID
		}
	}
	return events, known
}

func (m *TranscriptMapper) rememberLaunches(rec claudeTranscriptRecord) {
	for _, block := range claudeContentBlocks(rec.Message.Content) {
		if block.Type != "tool_use" || block.ID == "" {
			continue
		}
		if block.Name != "Bash" && block.Name != "Monitor" && block.Name != "Agent" {
			continue
		}
		var input struct {
			Command     string `json:"command"`
			Description string `json:"description"`
		}
		_ = json.Unmarshal(block.Input, &input)
		if _, exists := m.launches[block.ID]; !exists {
			m.order = append(m.order, block.ID)
		}
		m.launches[block.ID] = taskLaunch{
			name:        block.Name,
			description: strings.TrimSpace(input.Description),
			command:     strings.TrimSpace(input.Command),
			timestamp:   rec.Timestamp,
		}
	}
	for len(m.order) > maxRememberedLaunches {
		delete(m.launches, m.order[0])
		m.order = m.order[1:]
	}
}

type claudeBackgroundResult struct {
	BackgroundTaskID string `json:"backgroundTaskId"`
	TaskID           string `json:"taskId"`
	Status           string `json:"status"`
	AgentID          string `json:"agentId"`
	Description      string `json:"description"`
	OutputFile       string `json:"outputFile"`
}

var (
	backgroundShellID = regexp.MustCompile(`(?:running in background with ID: |backgrounded by user with ID: |\(ID: )([A-Za-z0-9_-]+)`)
	backgroundOutput  = regexp.MustCompile(`Output is being written to: (\S+?\.output)\b`)
	monitorStarted    = regexp.MustCompile(`^Monitor started \(task ([A-Za-z0-9_-]+)`)
)

func (m *TranscriptMapper) launchEvents(rec claudeTranscriptRecord) []domain.BlockTranscriptEvent {
	var result claudeBackgroundResult
	if len(rec.ToolUseResult) > 0 {
		_ = json.Unmarshal(rec.ToolUseResult, &result)
	}
	var events []domain.BlockTranscriptEvent
	for _, block := range claudeContentBlocks(rec.Message.Content) {
		if block.Type != "tool_result" || block.ToolUseID == "" || block.IsError {
			continue
		}
		launch, remembered := m.launches[block.ToolUseID]
		delete(m.launches, block.ToolUseID)
		text := claudeFlattenText(block.Content)
		task, tool, ok := launchedTask(result, launch, remembered, text)
		if !ok {
			continue
		}
		task.ToolUseID = block.ToolUseID
		task.Status = domain.BackgroundTaskRunning
		task.StartedAt = rec.Timestamp
		task.HarnessVersion = strings.TrimSpace(rec.Version)
		if remembered {
			if launch.timestamp != "" {
				task.StartedAt = launch.timestamp
			}
			task.Description = launch.description
			task.Command = launch.command
		}
		if task.Kind == domain.BackgroundTaskAgent && result.Description != "" {
			task.Description = result.Description
		}
		if task.Kind == domain.BackgroundTaskAgent {
			task.Command = ""
		}
		if task.Description == "" {
			task.Description = task.Command
		}
		if event, ok := m.taskEvent(task, tool); ok {
			events = append(events, event)
		}
	}
	return events
}

func launchedTask(result claudeBackgroundResult, launch taskLaunch, remembered bool, text string) (domain.BackgroundTask, string, bool) {
	switch {
	case result.Status == "async_launched" && result.AgentID != "":
		return domain.BackgroundTask{TaskID: result.AgentID, Kind: domain.BackgroundTaskAgent, OutputFile: result.OutputFile}, "Agent", true
	case (remembered && launch.name == "Monitor") || monitorStarted.MatchString(text):
		id := result.TaskID
		if match := monitorStarted.FindStringSubmatch(text); id == "" && match != nil {
			id = match[1]
		}
		if id == "" {
			return domain.BackgroundTask{}, "", false
		}
		return domain.BackgroundTask{TaskID: id, Kind: domain.BackgroundTaskMonitor}, "Monitor", true
	}
	id := result.BackgroundTaskID
	if id == "" {
		if match := backgroundShellID.FindStringSubmatch(text); match != nil && strings.Contains(text, "Output is being written to: ") {
			id = match[1]
		}
	}
	if id == "" {
		return domain.BackgroundTask{}, "", false
	}
	task := domain.BackgroundTask{TaskID: id, Kind: domain.BackgroundTaskShell}
	if match := backgroundOutput.FindStringSubmatch(text); match != nil {
		task.OutputFile = match[1]
	}
	tool := "Bash"
	if remembered {
		tool = launch.name
	}
	return task, tool, true
}

func (m *TranscriptMapper) notificationEvents(content, timestamp string) []domain.BlockTranscriptEvent {
	note, ok := parseTaskNotification(content)
	if !ok {
		return nil
	}
	key := note.taskID + "\x00" + string(note.status)
	if _, dup := m.seen[key]; dup {
		return nil
	}
	m.seen[key] = struct{}{}
	previous, known := m.tasks[note.taskID]
	task := previous.task
	tool := previous.tool
	if !known {
		task = domain.BackgroundTask{TaskID: note.taskID, Kind: inferTaskKind(note)}
		tool = ""
	}
	task.Status = note.status
	if note.toolUseID != "" {
		task.ToolUseID = note.toolUseID
	}
	if note.outputFile != "" {
		task.OutputFile = note.outputFile
	}
	task.Summary = note.summary
	task.ExitCode = exitCodeFromSummary(note.summary)
	task.DurationMs = note.durationMs
	task.EndedAt = timestamp
	event, ok := m.taskEvent(task, tool)
	if !ok {
		return nil
	}
	return []domain.BlockTranscriptEvent{event}
}

func (m *TranscriptMapper) taskEvent(task domain.BackgroundTask, tool string) (domain.BlockTranscriptEvent, bool) {
	encoded, err := json.Marshal(task)
	if err != nil {
		return domain.BlockTranscriptEvent{}, false
	}
	m.tasks[task.TaskID] = knownTask{task: task, tool: tool}
	if task.Status.Finished() {
		m.rememberFinished(task.TaskID)
	}
	return domain.BlockTranscriptEvent{
		Kind:      domain.BlockEventTaskUpdate,
		SourceID:  task.TaskID,
		ToolName:  tool,
		ToolUseID: task.ToolUseID,
		Text:      task.Summary,
		Detail:    string(encoded),
	}, true
}

func (m *TranscriptMapper) rememberFinished(id string) {
	m.finished = append(m.finished, id)
	for len(m.finished) > maxRememberedFinished {
		oldest := m.finished[0]
		m.finished = m.finished[1:]
		if slices.Contains(m.finished, oldest) {
			continue
		}
		if known, ok := m.tasks[oldest]; ok && known.task.Status.Finished() {
			delete(m.tasks, oldest)
		}
		for key := range m.seen {
			if strings.HasPrefix(key, oldest+"\x00") {
				delete(m.seen, key)
			}
		}
	}
}

func inferTaskKind(note taskNotification) domain.BackgroundTaskKind {
	switch {
	case strings.HasPrefix(note.summary, `Agent "`):
		return domain.BackgroundTaskAgent
	case strings.HasPrefix(note.summary, "Monitor "):
		return domain.BackgroundTaskMonitor
	default:
		return domain.BackgroundTaskShell
	}
}

type taskNotification struct {
	taskID     string
	toolUseID  string
	outputFile string
	status     domain.BackgroundTaskStatus
	summary    string
	durationMs *int64
}

func parseTaskNotification(content string) (taskNotification, bool) {
	content = strings.TrimSpace(content)
	start := strings.Index(content, "<task-notification>")
	end := strings.LastIndex(content, "</task-notification>")
	if start < 0 || end < start {
		return taskNotification{}, false
	}
	body := content[start+len("<task-notification>") : end]
	tags := topLevelTags(body)
	id := tags["task-id"]
	if id == "" || strings.ContainsAny(id, "<> \n") {
		return taskNotification{}, false
	}
	status, ok := domain.ParseBackgroundTaskStatus(tags["status"])
	if !ok || status == domain.BackgroundTaskRunning {
		return taskNotification{}, false
	}
	note := taskNotification{
		taskID:     id,
		toolUseID:  tags["tool-use-id"],
		outputFile: html.UnescapeString(tags["output-file"]),
		status:     status,
		summary:    html.UnescapeString(tags["summary"]),
	}
	if usage, ok := tags["usage"]; ok {
		if match := durationTag.FindStringSubmatch(usage); match != nil {
			if value, err := strconv.ParseInt(match[1], 10, 64); err == nil {
				note.durationMs = &value
			}
		}
	}
	return note, true
}

var (
	durationTag     = regexp.MustCompile(`<duration_ms>\s*(\d+)\s*</duration_ms>`)
	summaryExitCode = regexp.MustCompile(`(?:\(exit code (-?\d+)\)|with exit code (-?\d+))$`)
)

func exitCodeFromSummary(summary string) *int {
	match := summaryExitCode.FindStringSubmatch(strings.TrimSpace(summary))
	if match == nil {
		return nil
	}
	raw := match[1]
	if raw == "" {
		raw = match[2]
	}
	code, err := strconv.Atoi(raw)
	if err != nil {
		return nil
	}
	return &code
}

func topLevelTags(body string) map[string]string {
	tags := map[string]string{}
	for pos := 0; pos < len(body); {
		open := strings.IndexByte(body[pos:], '<')
		if open < 0 {
			break
		}
		open += pos
		closeAngle := strings.IndexByte(body[open:], '>')
		if closeAngle < 0 {
			break
		}
		name := body[open+1 : open+closeAngle]
		contentStart := open + closeAngle + 1
		if !validTagName(name) {
			pos = open + 1
			continue
		}
		terminator := "</" + name + ">"
		end := strings.Index(body[contentStart:], terminator)
		if end < 0 {
			pos = contentStart
			continue
		}
		if _, exists := tags[name]; !exists {
			tags[name] = strings.TrimSpace(body[contentStart : contentStart+end])
		}
		pos = contentStart + end + len(terminator)
	}
	return tags
}

func validTagName(name string) bool {
	if name == "" {
		return false
	}
	for _, r := range name {
		if (r < 'a' || r > 'z') && r != '_' && r != '-' {
			return false
		}
	}
	return true
}
