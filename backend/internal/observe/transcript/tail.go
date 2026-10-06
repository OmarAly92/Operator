package transcript

import (
	"bufio"
	"bytes"
	"context"
	"io"
	"os"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/blocktranscript"
	"github.com/OmarAly92/operator/backend/internal/domain"
)

// maxTranscriptLineBytes bounds one record. A line larger than this is a
// generated artifact, not something a phone renders; it is counted and skipped
// rather than buffered.
const maxTranscriptLineBytes = 1 << 20

// Sink receives one mapped transcript event. blockevent.Service satisfies it.
type Sink interface {
	RecordTranscript(ctx context.Context, sessionID domain.SessionID, harness string, ev domain.BlockTranscriptEvent) error
}

// OffsetStore persists the read cursor so a daemon restart resumes instead of
// re-emitting.
type OffsetStore interface {
	GetTranscriptOffset(ctx context.Context, sessionID string) (string, int64, bool, error)
	UpsertTranscriptOffset(ctx context.Context, sessionID, path string, offset int64, at time.Time) error
}

// InterruptSink is told when a main transcript ends on a user interrupt, which
// some harnesses record there and announce through no hook.
type InterruptSink interface {
	ApplyUserInterrupt(ctx context.Context, sessionID domain.SessionID) error
}

type tail struct {
	sessionID  domain.SessionID
	harness    string
	path       string
	agentID    string
	offset     int64
	lastModel  string
	unknown    int
	logged     int
	interrupts InterruptSink
	mapper     blocktranscript.MapFunc
}

const primeWindowBytes = 4 << 20

func primeMapper(file *os.File, offset int64, mapper blocktranscript.MapFunc) {
	start := max(0, offset-primeWindowBytes)
	if _, err := file.Seek(start, io.SeekStart); err != nil {
		return
	}
	reader := bufio.NewReaderSize(io.LimitReader(file, offset-start), 64<<10)
	if start > 0 {
		if _, err := reader.ReadBytes('\n'); err != nil {
			return
		}
	}
	for {
		line, err := reader.ReadBytes('\n')
		if err != nil {
			return
		}
		record := bytes.TrimRight(line, "\r\n")
		if len(record) == 0 || len(record) > maxTranscriptLineBytes {
			continue
		}
		mapper(record)
	}
}

func offsetKey(sessionID domain.SessionID, agentID string) string {
	if agentID == "" {
		return string(sessionID)
	}
	return string(sessionID) + "#" + agentID
}

func (t *tail) pump(ctx context.Context, sink Sink, offsets OffsetStore, now func() time.Time) error {
	file, err := os.Open(t.path)
	if err != nil {
		return err
	}
	defer func() { _ = file.Close() }()
	info, err := file.Stat()
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() {
		return nil
	}
	if info.Size() < t.offset {
		t.offset = 0
		t.lastModel = ""
		t.mapper = nil
	}
	if info.Size() == t.offset {
		return nil
	}
	if t.mapper == nil {
		t.mapper = blocktranscript.NewMapper(t.harness, t.agentID)
		if t.mapper != nil && t.offset > 0 {
			primeMapper(file, t.offset, t.mapper)
		}
	}
	if _, err := file.Seek(t.offset, io.SeekStart); err != nil {
		return err
	}

	reader := bufio.NewReaderSize(file, 64<<10)
	committed := t.offset
	consumed := t.offset
	// Only an interrupt that is the last turn record read is reported: a
	// later record means the user already started the next turn.
	interrupted := false
	for {
		if err := ctx.Err(); err != nil {
			return err
		}
		line, readErr := reader.ReadBytes('\n')
		if readErr != nil {
			break
		}
		consumed += int64(len(line))
		record := bytes.TrimRight(line, "\r\n")
		if len(bytes.TrimSpace(record)) == 0 {
			committed = consumed
			continue
		}
		if len(record) > maxTranscriptLineBytes {
			t.unknown++
			committed = consumed
			continue
		}
		var events []domain.BlockTranscriptEvent
		known := false
		if t.mapper != nil {
			events, known = t.mapper(record)
		}
		if !known {
			t.unknown++
		}
		if t.agentID == "" {
			if marker, turn := blocktranscript.Interrupt(t.harness, record); turn {
				interrupted = marker
			}
		}
		for _, event := range events {
			if event.Kind == domain.BlockEventTurnModel {
				if event.Text == t.lastModel {
					continue
				}
				t.lastModel = event.Text
			}
			if err := sink.RecordTranscript(ctx, t.sessionID, t.harness, event); err != nil {
				t.offset = committed
				_ = offsets.UpsertTranscriptOffset(ctx, offsetKey(t.sessionID, t.agentID), t.path, t.offset, now())
				return err
			}
		}
		committed = consumed
	}
	if committed == t.offset {
		return nil
	}
	t.offset = committed
	if err := offsets.UpsertTranscriptOffset(ctx, offsetKey(t.sessionID, t.agentID), t.path, t.offset, now()); err != nil {
		return err
	}
	if interrupted && t.interrupts != nil {
		return t.interrupts.ApplyUserInterrupt(ctx, t.sessionID)
	}
	return nil
}
