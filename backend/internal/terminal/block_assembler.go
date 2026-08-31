package terminal

import (
	"bytes"
	"strconv"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/terminalcapture"
	"github.com/OmarAly92/operator/packages/terminal/go/marks"
)

type CaptureCursor = terminalcapture.CaptureCursor

type BlockAssembler struct {
	TerminalID  string
	SessionID   string
	AlternateOn bool

	epoch   string
	now     func() time.Time
	pending *pendingBlock
}

type pendingBlock struct {
	id            string
	idFromExt     bool
	startOffset   int64
	lastOffset    int64
	sawPromptA    bool
	outputStarted bool
	command       string
	cwd           string
	branch        string
	startedAt     time.Time
	finishedHint  time.Time
	extExit       *int
	haveExtExit   bool
	raw           bytes.Buffer
}

func NewBlockAssembler(terminalID, sessionID, epoch string, alternateOn bool, now func() time.Time) *BlockAssembler {
	if now == nil {
		now = func() time.Time { return time.Now().UTC() }
	}
	return &BlockAssembler{
		TerminalID:  terminalID,
		SessionID:   sessionID,
		AlternateOn: alternateOn,
		epoch:       epoch,
		now:         now,
	}
}

func (a *BlockAssembler) Consume(tokens []marks.Token) []domain.Block {
	var out []domain.Block
	for _, tok := range tokens {
		if b, ok := a.step(tok); ok {
			out = append(out, b)
		}
	}
	return out
}

func (a *BlockAssembler) Gap() {
	a.pending = nil
}

func (a *BlockAssembler) Finish(final bool) []domain.Block {
	if !final || a.pending == nil {
		return nil
	}
	p := a.pending
	a.pending = nil
	if !p.outputStarted {
		return nil
	}
	finished := a.now()
	return []domain.Block{{
		TerminalID:   a.TerminalID,
		SourceID:     a.blockID(p),
		SessionID:    a.SessionID,
		Command:      p.command,
		Cwd:          p.cwd,
		GitBranch:    p.branch,
		ExitCode:     nil,
		RawOutput:    append([]byte(nil), p.raw.Bytes()...),
		StartedAt:    p.startedAt,
		FinishedAt:   finished,
		CaptureEpoch: a.epoch,
		StartOffset:  p.startOffset,
		EndOffset:    p.lastOffset,
		CreatedAt:    finished,
	}}
}

func (a *BlockAssembler) step(tok marks.Token) (domain.Block, bool) {
	if tok.Kind != marks.TokenMark {
		a.record(tok)
		return domain.Block{}, false
	}
	m := tok.Mark
	switch m.Kind {
	case "alt_screen_enter":
		a.AlternateOn = true
		return domain.Block{}, false
	case "alt_screen_leave":
		a.AlternateOn = false
		return domain.Block{}, false
	}

	if a.AlternateOn {
		switch m.Kind {
		case "command_end":
			return a.finishBlock(tok, m)
		case "extension":
			a.applyExtension(m, tok)
		}
		return domain.Block{}, false
	}

	switch m.Kind {
	case "extension":
		a.applyExtension(m, tok)
	case "prompt_start":
		a.startBlockAtA(tok)
	case "command_start":
		a.record(tok)
	case "output_start":
		if a.pending != nil {
			a.pending.outputStarted = true
		}
		a.record(tok)
	case "cwd_changed":
		if a.pending != nil && !a.pending.outputStarted && m.Path != "" {
			a.pending.cwd = m.Path
		}
		a.record(tok)
	case "command_end":
		return a.finishBlock(tok, m)
	default:
		a.record(tok)
	}
	return domain.Block{}, false
}

func (a *BlockAssembler) applyExtension(m marks.Mark, tok marks.Token) {
	if a.pending == nil {
		if a.AlternateOn {
			return
		}
		a.pending = &pendingBlock{startOffset: tok.Start, lastOffset: tok.Start}
	}
	p := a.pending
	if v := m.Fields["id"]; v != "" {
		p.id = v
		p.idFromExt = true
	}
	if v, ok := m.Fields["cmd"]; ok {
		p.command = v
	}
	if v := m.Fields["cwd"]; v != "" {
		p.cwd = v
	}
	if v := m.Fields["branch"]; v != "" {
		p.branch = v
	}
	if v := m.Fields["start_ms"]; v != "" {
		if t, ok := parseEpochMillis(v); ok {
			p.startedAt = t
		}
	}
	if v := m.Fields["end_ms"]; v != "" {
		if t, ok := parseEpochMillis(v); ok {
			p.finishedHint = t
		}
	}
	if v, ok := m.Fields["exit"]; ok {
		if n, err := strconv.Atoi(v); err == nil {
			p.extExit = &n
			p.haveExtExit = true
		}
	}
	a.record(tok)
}

func (a *BlockAssembler) startBlockAtA(tok marks.Token) {
	if a.pending != nil && !a.pending.sawPromptA && !a.pending.outputStarted {
		a.pending.sawPromptA = true
		a.record(tok)
		return
	}
	a.pending = &pendingBlock{
		startOffset: tok.Start,
		lastOffset:  tok.Start,
		sawPromptA:  true,
	}
	a.record(tok)
}

func (a *BlockAssembler) finishBlock(tok marks.Token, m marks.Mark) (domain.Block, bool) {
	if a.pending == nil {
		return domain.Block{}, false
	}
	p := a.pending
	if len(tok.Raw) > 0 {
		p.raw.Write(tok.Raw)
	}
	if tok.End > p.lastOffset {
		p.lastOffset = tok.End
	}

	var exit *int
	switch {
	case m.ExitCode != nil:
		exit = m.ExitCode
	case p.haveExtExit:
		exit = p.extExit
	}
	finished := p.finishedHint
	if finished.IsZero() {
		finished = a.now()
	}

	a.pending = nil
	return domain.Block{
		TerminalID:   a.TerminalID,
		SourceID:     a.blockID(p),
		SessionID:    a.SessionID,
		Command:      p.command,
		Cwd:          p.cwd,
		GitBranch:    p.branch,
		ExitCode:     exit,
		RawOutput:    append([]byte(nil), p.raw.Bytes()...),
		StartedAt:    p.startedAt,
		FinishedAt:   finished,
		CaptureEpoch: a.epoch,
		StartOffset:  p.startOffset,
		EndOffset:    tok.End,
		CreatedAt:    a.now(),
	}, true
}

func (a *BlockAssembler) record(tok marks.Token) {
	if a.pending == nil || a.AlternateOn {
		return
	}
	if len(tok.Raw) > 0 {
		a.pending.raw.Write(tok.Raw)
	}
	if tok.End > a.pending.lastOffset {
		a.pending.lastOffset = tok.End
	}
}

func (a *BlockAssembler) blockID(p *pendingBlock) string {
	if p.idFromExt && p.id != "" {
		return p.id
	}
	return sanitizeProtocolID("osc133-" + a.epoch + "-" + strconv.FormatInt(p.startOffset, 10))
}

func sanitizeProtocolID(s string) string {
	out := make([]byte, 0, len(s))
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c >= 'A' && c <= 'Z', c >= 'a' && c <= 'z', c >= '0' && c <= '9':
			out = append(out, c)
		case bytes.IndexByte([]byte("._~/:@!$&'()*+,;=-"), c) >= 0:
			out = append(out, c)
		default:
			out = append(out, '-')
		}
	}
	return string(out)
}

func parseEpochMillis(s string) (time.Time, bool) {
	if s == "" {
		return time.Time{}, false
	}
	var n int64
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c < '0' || c > '9' {
			return time.Time{}, false
		}
		n = n*10 + int64(c-'0')
	}
	return time.UnixMilli(n).UTC(), true
}
