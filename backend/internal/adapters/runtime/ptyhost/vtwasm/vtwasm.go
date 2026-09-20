// Package vtwasm runs the vt-core terminal parser as a WebAssembly module via
// wazero, keeping the backend free of cgo. The parser is passive: it never sits
// between the agent's PTY and an attached client.
package vtwasm

import (
	"context"
	"encoding/binary"
	"fmt"
	"sync"
	"time"

	"github.com/tetratelabs/wazero"
	"github.com/tetratelabs/wazero/api"
)

// Parser serializes every call into the wasm module behind mu. The module's
// linear memory is shared mutable state: pumpPTY's Feed calls race client
// goroutines' RenderTail/RenderStyledTail/Resize/AltActive calls on the same
// handle, and wazero gives no thread-safety guarantee across concurrent calls.
type Parser struct {
	runtime wazero.Runtime
	module  api.Module
	handle  uint32
	ctx     context.Context
	mu      sync.Mutex
}

// TerminalIdentity is what the mirror answers to XTVERSION (`CSI > 0 q`); it
// matches the TERM_PROGRAM the pty-host sets for the child.
const TerminalIdentity = "Operator"

type Limits struct {
	Rows  uint32
	Bytes uint32
}

type MemoryStats struct {
	ContentBytes uint32
	StyleEntries uint32
	Rows         uint32
	Blocks       uint32
}

func New(ctx context.Context, wasmModule []byte, cols, rows uint32, limits Limits) (*Parser, error) {
	rt := wazero.NewRuntime(ctx)
	mod, err := rt.Instantiate(ctx, wasmModule)
	if err != nil {
		_ = rt.Close(ctx)
		return nil, fmt.Errorf("vtwasm: instantiate: %w", err)
	}
	res, err := mod.ExportedFunction("vt_new").Call(ctx, uint64(cols), uint64(rows), uint64(limits.Rows), uint64(limits.Bytes))
	if err != nil || len(res) == 0 || res[0] == 0 {
		_ = rt.Close(ctx)
		return nil, fmt.Errorf("vtwasm: vt_new failed: %w", err)
	}
	p := &Parser{runtime: rt, module: mod, handle: uint32(res[0]), ctx: ctx}
	if err := p.setTerminalIdentity(TerminalIdentity); err != nil {
		_ = rt.Close(ctx)
		return nil, err
	}
	return p, nil
}

const memoryStatsBytes = 16

func (p *Parser) MemoryStats() (MemoryStats, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	res, err := p.module.ExportedFunction("vt_alloc").Call(p.ctx, memoryStatsBytes)
	if err != nil {
		return MemoryStats{}, fmt.Errorf("vtwasm: alloc stats: %w", err)
	}
	out := uint32(res[0])
	defer func() { _, _ = p.module.ExportedFunction("vt_free").Call(p.ctx, uint64(out), memoryStatsBytes) }()
	res, err = p.module.ExportedFunction("vt_memory_stats").Call(p.ctx, uint64(p.handle), uint64(out))
	if err != nil {
		return MemoryStats{}, fmt.Errorf("vtwasm: memory_stats: %w", err)
	}
	if res[0] != 1 {
		return MemoryStats{}, fmt.Errorf("vtwasm: memory_stats failed for handle %d", p.handle)
	}
	raw, ok := p.module.Memory().Read(out, memoryStatsBytes)
	if !ok {
		return MemoryStats{}, fmt.Errorf("vtwasm: read stats out of range")
	}
	return MemoryStats{
		ContentBytes: binary.LittleEndian.Uint32(raw[0:4]),
		StyleEntries: binary.LittleEndian.Uint32(raw[4:8]),
		Rows:         binary.LittleEndian.Uint32(raw[8:12]),
		Blocks:       binary.LittleEndian.Uint32(raw[12:16]),
	}, nil
}

func (p *Parser) setTerminalIdentity(name string) error {
	bytes := []byte(name)
	res, err := p.module.ExportedFunction("vt_alloc").Call(p.ctx, uint64(len(bytes)))
	if err != nil {
		return fmt.Errorf("vtwasm: alloc: %w", err)
	}
	ptr := uint32(res[0])
	defer func() { _, _ = p.module.ExportedFunction("vt_free").Call(p.ctx, uint64(ptr), uint64(len(bytes))) }()
	if !p.module.Memory().Write(ptr, bytes) {
		return fmt.Errorf("vtwasm: write identity out of range")
	}
	_, err = p.module.ExportedFunction("vt_set_terminal_identity").Call(p.ctx, uint64(p.handle), uint64(ptr), uint64(len(bytes)))
	return err
}

func (p *Parser) Feed(bytes []byte) error {
	return p.FeedAt(bytes, time.Now().UnixMilli())
}

func (p *Parser) FeedAt(bytes []byte, nowMs int64) error {
	if len(bytes) == 0 {
		return nil
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	res, err := p.module.ExportedFunction("vt_alloc").Call(p.ctx, uint64(len(bytes)))
	if err != nil {
		return fmt.Errorf("vtwasm: alloc: %w", err)
	}
	ptr := uint32(res[0])
	defer func() { _, _ = p.module.ExportedFunction("vt_free").Call(p.ctx, uint64(ptr), uint64(len(bytes))) }()

	if !p.module.Memory().Write(ptr, bytes) {
		return fmt.Errorf("vtwasm: write %d bytes at %d out of range", len(bytes), ptr)
	}
	_, err = p.module.ExportedFunction("vt_feed").Call(p.ctx, uint64(p.handle), uint64(ptr), uint64(len(bytes)), uint64(nowMs))
	return err
}

func (p *Parser) Tick(nowMs int64) (bool, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	res, err := p.module.ExportedFunction("vt_tick").Call(p.ctx, uint64(p.handle), uint64(nowMs))
	if err != nil {
		return false, fmt.Errorf("vtwasm: tick: %w", err)
	}
	return res[0] == 1, nil
}

const queryReplyBufferBytes = 4096

// TakeQueryReplies drains the terminal-query answers the mirror owes the child
// (DECRPM for a `CSI ? Pm $ p` request). The mirror is the only party present
// from the child's first byte, so it is the one that answers; the renderer core
// never does, or the child would hear every reply once per attached client.
func (p *Parser) TakeQueryReplies() ([]byte, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	res, err := p.module.ExportedFunction("vt_alloc").Call(p.ctx, queryReplyBufferBytes)
	if err != nil {
		return nil, fmt.Errorf("vtwasm: alloc reply buffer: %w", err)
	}
	out := uint32(res[0])
	defer func() { _, _ = p.module.ExportedFunction("vt_free").Call(p.ctx, uint64(out), queryReplyBufferBytes) }()
	res, err = p.module.ExportedFunction("vt_take_query_replies").Call(p.ctx, uint64(p.handle), uint64(out), queryReplyBufferBytes)
	if err != nil {
		return nil, fmt.Errorf("vtwasm: take_query_replies: %w", err)
	}
	switch written := uint32(res[0]); written {
	case 0:
		return nil, nil
	case renderErr, renderTooBig:
		return nil, fmt.Errorf("vtwasm: take_query_replies failed for handle %d", p.handle)
	default:
		bytes, ok := p.module.Memory().Read(out, written)
		if !ok {
			return nil, fmt.Errorf("vtwasm: read %d bytes at %d out of range", written, out)
		}
		return append([]byte(nil), bytes...), nil
	}
}

func (p *Parser) InSync() (bool, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	res, err := p.module.ExportedFunction("vt_in_sync").Call(p.ctx, uint64(p.handle))
	if err != nil {
		return false, fmt.Errorf("vtwasm: in_sync: %w", err)
	}
	return res[0] == 1, nil
}

func (p *Parser) Close() error { return p.runtime.Close(p.ctx) }

const (
	renderBufferBytes = 1 << 20
	renderErr         = ^uint32(0)
	renderTooBig      = ^uint32(0) - 1
)

// RenderTail returns ("", nil) for a genuinely empty screen. Errors are errors:
// the caller must never treat one as "fall back to the raw ring", or the
// platform-divergence bug this parser exists to kill comes back through the
// side door.
func (p *Parser) renderWith(fn, label string, lines int) (string, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	res, err := p.module.ExportedFunction("vt_alloc").Call(p.ctx, renderBufferBytes)
	if err != nil {
		return "", fmt.Errorf("vtwasm: alloc render buffer: %w", err)
	}
	out := uint32(res[0])
	defer func() { _, _ = p.module.ExportedFunction("vt_free").Call(p.ctx, uint64(out), renderBufferBytes) }()

	res, err = p.module.ExportedFunction(fn).
		Call(p.ctx, uint64(p.handle), uint64(lines), uint64(out), renderBufferBytes)
	if err != nil {
		return "", fmt.Errorf("vtwasm: %s: %w", label, err)
	}
	switch written := uint32(res[0]); written {
	case 0:
		return "", nil
	case renderErr:
		return "", fmt.Errorf("vtwasm: %s failed for handle %d", label, p.handle)
	case renderTooBig:
		return "", fmt.Errorf("vtwasm: %s exceeds %d bytes", label, renderBufferBytes)
	default:
		bytes, ok := p.module.Memory().Read(out, written)
		if !ok {
			return "", fmt.Errorf("vtwasm: read %d bytes at %d out of range", written, out)
		}
		return string(bytes), nil
	}
}

func (p *Parser) RenderTail(lines int) (string, error) {
	return p.renderWith("vt_render", "render", lines)
}

// RenderStyledTail mirrors RenderTail but calls vt_render_styled, which
// re-emits SGR escapes at each style-run boundary.
func (p *Parser) RenderStyledTail(lines int) (string, error) {
	return p.renderWith("vt_render_styled", "render_styled", lines)
}

// Replay returns the bytes that reproduce the terminal's CURRENT state on a
// freshly attached client: CR-LF terminated styled rows, the alternate-screen
// mode set when the child is in it, and a final cursor placement.
//
// This — not the raw output ring — is what attach replay must send. A byte log
// only reproduces the screen when it is replayed into the exact geometry that
// produced it; a grid repaint is geometry-independent by construction.
func (p *Parser) Replay(lines int) (string, error) {
	return p.renderWith("vt_replay", "replay", lines)
}

func (p *Parser) Resize(cols, rows uint32) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	_, err := p.module.ExportedFunction("vt_resize").
		Call(p.ctx, uint64(p.handle), uint64(cols), uint64(rows))
	return err
}

func (p *Parser) AltActive() (bool, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	res, err := p.module.ExportedFunction("vt_alt_active").Call(p.ctx, uint64(p.handle))
	if err != nil {
		return false, fmt.Errorf("vtwasm: alt_active: %w", err)
	}
	return res[0] == 1, nil
}
