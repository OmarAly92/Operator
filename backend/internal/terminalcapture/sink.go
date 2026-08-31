package terminalcapture

import (
	"context"
	"errors"
	"io"
)

type Sink struct {
	journal *Journal
}

func NewSink(j *Journal) *Sink {
	return &Sink{journal: j}
}

func (s *Sink) Run(ctx context.Context, r io.Reader) error {
	buf := make([]byte, 64<<10)
	for {
		select {
		case <-ctx.Done():
			return errors.Join(ctx.Err(), s.journal.Close())
		default:
		}

		n, readErr := r.Read(buf)
		if n > 0 {
			if _, writeErr := s.journal.Write(buf[:n]); writeErr != nil {
				return errors.Join(writeErr, s.journal.Close())
			}
		}
		if readErr != nil {
			if ctxErr := ctx.Err(); ctxErr != nil {
				return errors.Join(ctxErr, s.journal.Close())
			}
			if errors.Is(readErr, io.EOF) {
				return s.journal.Close()
			}
			return errors.Join(readErr, s.journal.Close())
		}
	}
}
