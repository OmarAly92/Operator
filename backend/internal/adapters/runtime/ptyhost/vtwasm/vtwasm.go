// Package vtwasm runs the vt-core terminal parser as a WebAssembly module via
// wazero, keeping the backend free of cgo. The parser is passive: it never sits
// between the agent's PTY and an attached client.
package vtwasm

import (
	"context"
	"fmt"

	"github.com/tetratelabs/wazero"
	"github.com/tetratelabs/wazero/api"
)

type Parser struct {
	runtime wazero.Runtime
	module  api.Module
	handle  uint32
	ctx     context.Context
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
	res, err := p.module.ExportedFunction("vt_alloc").Call(p.ctx, uint64(len(bytes)))
	if err != nil {
		return fmt.Errorf("vtwasm: alloc: %w", err)
	}
	ptr := uint32(res[0])
	defer p.module.ExportedFunction("vt_free").Call(p.ctx, uint64(ptr), uint64(len(bytes)))

	if !p.module.Memory().Write(ptr, bytes) {
		return fmt.Errorf("vtwasm: write %d bytes at %d out of range", len(bytes), ptr)
	}
	_, err = p.module.ExportedFunction("vt_feed").Call(p.ctx, uint64(p.handle), uint64(ptr), uint64(len(bytes)))
	return err
}

func (p *Parser) Close() error { return p.runtime.Close(p.ctx) }
