// Package vtwasm runs the vt-core terminal parser as a WebAssembly module via
// wazero, keeping the backend free of cgo. The parser is passive: it never sits
// between the agent's PTY and an attached client.
package vtwasm

import (
	"context"
	"fmt"
	"sync"

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

func New(ctx context.Context, wasmModule []byte, cols, rows, scrollback uint32) (*Parser, error) {
	rt := wazero.NewRuntime(ctx)
	mod, err := rt.Instantiate(ctx, wasmModule)
	if err != nil {
		_ = rt.Close(ctx)
		return nil, fmt.Errorf("vtwasm: instantiate: %w", err)
	}
	res, err := mod.ExportedFunction("vt_new").Call(ctx, uint64(cols), uint64(rows), uint64(scrollback))
	if err != nil || len(res) == 0 || res[0] == 0 {
		_ = rt.Close(ctx)
		return nil, fmt.Errorf("vtwasm: vt_new failed: %w", err)
	}
	return &Parser{runtime: rt, module: mod, handle: uint32(res[0]), ctx: ctx}, nil
}

func (p *Parser) Feed(bytes []byte) error {
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
	_, err = p.module.ExportedFunction("vt_feed").Call(p.ctx, uint64(p.handle), uint64(ptr), uint64(len(bytes)))
	return err
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
