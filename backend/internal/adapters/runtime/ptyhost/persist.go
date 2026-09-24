package ptyhost

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/ptyregistry"
	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
)

const (
	historyMagic         = "OPRVT1\n"
	historyDirName       = "pty-host-history"
	historyFileSuffix    = ".vt"
	historyTempSuffix    = ".vt.tmp"
	persistInterval      = 60 * time.Second
	persistHistoryChunks = 20
	persistMaxBytes      = 4 << 20
	historyRetention     = 7 * 24 * time.Hour
)

func historyDir() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".operator", historyDirName), nil
}

func historyPath(sessionID string) (string, error) {
	dir, err := historyDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, sessionID+historyFileSuffix), nil
}

func writeHistoryFile(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	tmp := strings.TrimSuffix(path, historyFileSuffix) + historyTempSuffix
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func removeHistory(sessionID string) error {
	path, err := historyPath(sessionID)
	if err != nil {
		return err
	}
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}

func pruneHistory(now time.Time, live func(sessionID string) bool) error {
	dir, err := historyDir()
	if err != nil {
		return err
	}
	entries, err := os.ReadDir(dir)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	for _, entry := range entries {
		name := entry.Name()
		id, ok := strings.CutSuffix(name, historyTempSuffix)
		if !ok {
			id, ok = strings.CutSuffix(name, historyFileSuffix)
		}
		if !ok || live(id) {
			continue
		}
		info, err := entry.Info()
		if err != nil || now.Sub(info.ModTime()) < historyRetention {
			continue
		}
		_ = os.Remove(filepath.Join(dir, name))
	}
	return nil
}

func pruneStaleHistory(now time.Time, creating string) {
	entries, err := ptyregistry.List()
	if err != nil {
		return
	}
	keep := make(map[string]bool, len(entries)+1)
	keep[creating] = true
	for _, entry := range entries {
		keep[entry.SessionID] = true
	}
	_ = pruneHistory(now, func(sessionID string) bool { return keep[sessionID] })
}

func seedMirror(parser *vtwasm.Parser, path string) (bool, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if !bytes.HasPrefix(data, []byte(historyMagic)) {
		return false, errors.New("ptyhost: history file has no OPRVT1 header")
	}
	if err := parser.Feed(data[len(historyMagic):]); err != nil {
		return false, err
	}
	if err := parser.Feed(respawnBoundary(0, false)); err != nil {
		return false, err
	}
	if _, err := parser.TakeQueryReplies(); err != nil {
		return false, err
	}
	return true, nil
}

func prepareHistory(sessionID string, parser *vtwasm.Parser) string {
	if parser == nil {
		return ""
	}
	path, err := historyPath(sessionID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "pty-host [%s]: history path: %v\n", sessionID, err)
		return ""
	}
	if _, err := seedMirror(parser, path); err != nil {
		fmt.Fprintf(os.Stderr, "pty-host [%s]: seed history: %v\n", sessionID, err)
	}
	return path
}

func (h *host) historyMaxBytes() int {
	if h.cfg.HistoryMaxBytes > 0 {
		return h.cfg.HistoryMaxBytes
	}
	return persistMaxBytes
}

func (h *host) historySnapshot() []byte {
	parser := h.currentParser()
	if parser == nil {
		return nil
	}
	if err := parser.TouchHistory(); err != nil {
		h.logf("rewrap history for persistence: %v", err)
	}
	h.mu.Lock()
	frame, origin := h.replayFrameLocked()
	h.mu.Unlock()
	if frame == nil {
		return nil
	}
	limit := h.historyMaxBytes()
	payload := frame[frameHeaderBytes:]
	if len(historyMagic)+len(payload) > limit {
		return nil
	}
	out := make([]byte, 0, len(historyMagic)+len(payload))
	out = append(out, historyMagic...)
	out = append(out, payload...)
	if origin == vtwasm.HistoryBefore {
		return out
	}
	before := origin
	for range persistHistoryChunks {
		chunk, next, ok, err := parser.HistoryChunk(before, MaxOutputLines, vtwasm.HistoryChunkRows)
		if err != nil {
			h.logf("persist history chunk: %v", err)
			break
		}
		if !ok || len(out)+len(chunk) > limit {
			break
		}
		out = append(out, chunk...)
		before = next
	}
	return out
}

func (h *host) persistHistory() {
	if h.cfg.HistoryPath == "" {
		return
	}
	h.persistMu.Lock()
	defer h.persistMu.Unlock()
	h.respawnMu.Lock()
	defer h.respawnMu.Unlock()
	h.mu.Lock()
	fed := h.fedBytes
	h.mu.Unlock()
	if fed == h.persistedBytes {
		return
	}
	snapshot := h.historySnapshot()
	if snapshot == nil {
		return
	}
	if err := writeHistoryFile(h.cfg.HistoryPath, snapshot); err != nil {
		h.logf("persist history: %v", err)
		return
	}
	h.persistedBytes = fed
}

func (h *host) runHistoryPersist() {
	if h.cfg.HistoryPath == "" || h.cfg.PersistInterval <= 0 {
		return
	}
	ticker := time.NewTicker(h.cfg.PersistInterval)
	defer ticker.Stop()
	for {
		select {
		case <-h.shutdownC:
			return
		case <-ticker.C:
			h.persistHistory()
		}
	}
}
