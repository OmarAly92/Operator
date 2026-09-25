package ptyhost

import (
	"encoding/json"
	"net"
	"sync"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

var _ ports.TerminalProgramReader = (*Runtime)(nil)

type programWatch struct {
	mu      sync.Mutex
	conn    net.Conn
	stopped bool
	done    chan struct{}
}

func (w *programWatch) stop() {
	w.mu.Lock()
	w.stopped = true
	conn := w.conn
	w.mu.Unlock()
	if conn != nil {
		_ = conn.Close()
	}
}

func (w *programWatch) attach(conn net.Conn) bool {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.stopped {
		return false
	}
	w.conn = conn
	return true
}

func (r *Runtime) ensureProgramWatch(id string, sess *hostSession) {
	if sess == nil || sess.addr == "" {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.sessions[id] != sess {
		return
	}
	r.programMu.Lock()
	if _, running := r.programWatches[id]; running {
		r.programMu.Unlock()
		return
	}
	w := &programWatch{done: make(chan struct{})}
	r.programWatches[id] = w
	r.programMu.Unlock()
	go r.runProgramWatch(id, sess.addr, w)
}

func (r *Runtime) runProgramWatch(id, addr string, w *programWatch) {
	defer close(w.done)
	defer func() {
		r.programMu.Lock()
		current := r.programWatches[id] == w
		if current {
			delete(r.programWatches, id)
		}
		r.programMu.Unlock()
		if current {
			r.recordProgramEvent(id, ProgramEventPayload{Kind: ProgramEventTitle})
		}
	}()
	conn, err := dialHost(addr, dialTimeout)
	if err != nil {
		return
	}
	if !w.attach(conn) {
		_ = conn.Close()
		return
	}
	defer func() { _ = conn.Close() }()
	frame, _ := EncodeMessage(MsgWatchReq, nil)
	if _, err := conn.Write(frame); err != nil {
		return
	}
	parser := NewMessageParser(func(msgType byte, payload []byte) {
		if msgType != MsgProgramEvent {
			return
		}
		var event ProgramEventPayload
		if json.Unmarshal(payload, &event) == nil {
			r.recordProgramEvent(id, event)
		}
	})
	buf := make([]byte, 4096)
	for {
		n, err := conn.Read(buf)
		if n > 0 {
			parser.Feed(buf[:n])
		}
		if err != nil {
			return
		}
	}
}

func (r *Runtime) stopProgramWatch(id string) {
	r.programMu.Lock()
	w := r.programWatches[id]
	delete(r.programWatches, id)
	r.programMu.Unlock()
	if w != nil {
		w.stop()
		<-w.done
	}
	r.recordProgramEvent(id, ProgramEventPayload{Kind: ProgramEventTitle})
}

func (r *Runtime) recordProgramEvent(id string, event ProgramEventPayload) {
	var out ports.TerminalProgramEvent
	switch event.Kind {
	case ProgramEventTitle:
		r.programMu.Lock()
		if r.titles[id] == event.Title {
			r.programMu.Unlock()
			return
		}
		if event.Title == "" {
			delete(r.titles, id)
		} else {
			r.titles[id] = event.Title
		}
		r.programMu.Unlock()
		out = ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle, Title: event.Title}
	case ProgramEventNotification:
		out = ports.TerminalProgramEvent{Kind: ports.TerminalProgramNotification, Title: event.Title, Body: event.Body}
	default:
		return
	}
	r.programMu.Lock()
	listeners := make([]func(string, ports.TerminalProgramEvent), 0, len(r.programListeners))
	for _, fn := range r.programListeners {
		listeners = append(listeners, fn)
	}
	r.programMu.Unlock()
	for _, fn := range listeners {
		fn(id, out)
	}
}

func (r *Runtime) TerminalTitles() map[string]string {
	r.programMu.Lock()
	defer r.programMu.Unlock()
	titles := make(map[string]string, len(r.titles))
	for id, title := range r.titles {
		titles[id] = title
	}
	return titles
}

func (r *Runtime) WatchTerminalPrograms(fn func(handleID string, event ports.TerminalProgramEvent)) func() {
	r.programMu.Lock()
	id := r.nextProgramListener
	r.nextProgramListener++
	r.programListeners[id] = fn
	r.programMu.Unlock()
	return func() {
		r.programMu.Lock()
		delete(r.programListeners, id)
		r.programMu.Unlock()
	}
}

func (s *loopbackStream) SetAppearance(appearance ports.TerminalAppearance) error {
	payload, err := json.Marshal(AppearancePayload{
		CellWidth:  appearance.CellWidth,
		CellHeight: appearance.CellHeight,
		Foreground: appearance.Foreground,
		Background: appearance.Background,
	})
	if err != nil {
		return err
	}
	frame, err := EncodeMessage(MsgAppearance, payload)
	if err != nil {
		return err
	}
	_, err = s.conn.Write(frame)
	return err
}

var _ ports.AppearanceSetter = (*loopbackStream)(nil)
