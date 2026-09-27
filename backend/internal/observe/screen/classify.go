package screen

import (
	"strings"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

const (
	ScreenActiveConfirm   = 3 * time.Second
	ScreenQuestionConfirm = time.Second
	ScreenSettleConfirm   = 2 * time.Second
	ScreenQuietSettle     = 60 * time.Second
)

func Classify(agent any, event ports.TerminalProgramEvent) Observation {
	if event.Kind != ports.TerminalProgramActivity {
		return Observation{}
	}
	switch event.Activity {
	case ports.TerminalActivityActive:
		return Observation{Reading: domain.ScreenWorking, Confirm: ScreenActiveConfirm}
	case ports.TerminalActivityIdle, ports.TerminalActivityPrompting:
	default:
		return Observation{}
	}
	if reader, ok := agent.(ports.TerminalQuestionReader); ok {
		if question, ok := reader.ReadQuestion(event.Tail); ok {
			return Observation{Reading: domain.ScreenQuestion, Identity: question.Identity, Text: question.Text, Confirm: ScreenQuestionConfirm}
		}
	} else if event.Activity == ports.TerminalActivityPrompting {
		line := strings.TrimSpace(event.CursorLine)
		return Observation{Reading: domain.ScreenQuestion, Identity: strings.Join(strings.Fields(line), " "), Text: line, Confirm: ScreenQuestionConfirm}
	}
	detector, ok := agent.(ports.TerminalActivityDetector)
	if !ok {
		return Observation{Reading: domain.ScreenSettled, Text: turnSummary(agent, event.Summary), Confirm: ScreenQuietSettle}
	}
	state, ok := detector.DetectTerminalActivity(event.Tail)
	if !ok {
		return Observation{}
	}
	switch state {
	case domain.ActivityIdle:
		return Observation{Reading: domain.ScreenSettled, Text: turnSummary(agent, event.Summary), Confirm: ScreenSettleConfirm}
	case domain.ActivityWaitingInput:
		return Observation{Reading: domain.ScreenWaiting, Text: turnSummary(agent, event.Summary), Confirm: ScreenSettleConfirm}
	case domain.ActivityActive:
		return Observation{Reading: domain.ScreenWorking, Confirm: ScreenActiveConfirm}
	default:
		return Observation{}
	}
}

func turnSummary(agent any, summary string) string {
	if reader, ok := agent.(ports.TerminalSummaryReader); ok {
		text, _ := reader.ReadTurnSummary(summary)
		return text
	}
	return defaultTurnSummary(summary)
}

func defaultTurnSummary(summary string) string {
	var kept []string
	for _, line := range strings.Split(summary, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.Trim(line, "─━═╌┄│╭╮╰╯ ") == "" {
			continue
		}
		kept = append(kept, line)
	}
	return strings.Join(kept[max(0, len(kept)-6):], "\n")
}
