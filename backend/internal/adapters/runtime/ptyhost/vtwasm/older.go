package vtwasm

import (
	"encoding/binary"
	"fmt"
)

const OlderChunkRows = 2048

type ColdStats struct {
	Rows           uint32
	Bytes          uint32
	Cap            uint32
	FirstStableRow uint64
}

const coldStatsBytes = 20

func (p *Parser) ColdStats() (ColdStats, error) {
	raw, err := p.readStruct("vt_cold_stats", coldStatsBytes)
	if err != nil {
		return ColdStats{}, err
	}
	return ColdStats{
		Rows:           binary.LittleEndian.Uint32(raw[0:4]),
		Bytes:          binary.LittleEndian.Uint32(raw[4:8]),
		Cap:            binary.LittleEndian.Uint32(raw[8:12]),
		FirstStableRow: binary.LittleEndian.Uint64(raw[12:20]),
	}, nil
}

func (p *Parser) OlderChunk(before uint64, maxRows int) (string, uint64, bool, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	res, err := p.module.ExportedFunction("vt_alloc").Call(p.ctx, renderBufferBytes)
	if err != nil {
		return "", 0, false, fmt.Errorf("vtwasm: alloc older buffer: %w", err)
	}
	out := uint32(res[0])
	defer func() { _, _ = p.module.ExportedFunction("vt_free").Call(p.ctx, uint64(out), renderBufferBytes) }()
	res, err = p.module.ExportedFunction("vt_alloc").Call(p.ctx, historyNextBytes)
	if err != nil {
		return "", 0, false, fmt.Errorf("vtwasm: alloc older cursor: %w", err)
	}
	next := uint32(res[0])
	defer func() { _, _ = p.module.ExportedFunction("vt_free").Call(p.ctx, uint64(next), historyNextBytes) }()

	res, err = p.module.ExportedFunction("vt_older_chunk").
		Call(p.ctx, uint64(p.handle), before, uint64(maxRows), uint64(out), renderBufferBytes, uint64(next))
	if err != nil {
		return "", 0, false, fmt.Errorf("vtwasm: older_chunk: %w", err)
	}
	switch written := uint32(res[0]); written {
	case 0:
		return "", 0, false, nil
	case renderErr:
		return "", 0, false, fmt.Errorf("vtwasm: older_chunk failed for handle %d", p.handle)
	case renderTooBig:
		return "", 0, false, fmt.Errorf("vtwasm: older_chunk exceeds %d bytes", renderBufferBytes)
	default:
		body, ok := p.module.Memory().Read(out, written)
		if !ok {
			return "", 0, false, fmt.Errorf("vtwasm: read %d bytes at %d out of range", written, out)
		}
		cursor, ok := p.module.Memory().Read(next, historyNextBytes)
		if !ok {
			return "", 0, false, fmt.Errorf("vtwasm: read older cursor out of range")
		}
		return string(body), binary.LittleEndian.Uint64(cursor), true, nil
	}
}

const olderMarkBytes = 64

func (p *Parser) OlderMark() (string, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	res, err := p.module.ExportedFunction("vt_alloc").Call(p.ctx, olderMarkBytes)
	if err != nil {
		return "", fmt.Errorf("vtwasm: alloc older mark: %w", err)
	}
	out := uint32(res[0])
	defer func() { _, _ = p.module.ExportedFunction("vt_free").Call(p.ctx, uint64(out), olderMarkBytes) }()
	res, err = p.module.ExportedFunction("vt_older_mark").Call(p.ctx, uint64(p.handle), uint64(out), olderMarkBytes)
	if err != nil {
		return "", fmt.Errorf("vtwasm: older_mark: %w", err)
	}
	switch written := uint32(res[0]); written {
	case 0:
		return "", nil
	case renderErr, renderTooBig:
		return "", fmt.Errorf("vtwasm: older_mark failed for handle %d", p.handle)
	default:
		body, ok := p.module.Memory().Read(out, written)
		if !ok {
			return "", fmt.Errorf("vtwasm: read older mark out of range")
		}
		return string(body), nil
	}
}
