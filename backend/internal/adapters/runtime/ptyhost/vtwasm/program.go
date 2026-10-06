package vtwasm

import (
	"encoding/binary"
	"fmt"
)

type Notification struct {
	Title string
	Body  string
}

const (
	titleBufferBytes        = 4096
	notificationBufferBytes = 64 << 10
	knownColor              = 0x0100_0000
)

func (p *Parser) ProgramGeneration() (uint32, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	res, err := p.module.ExportedFunction("vt_program_generation").Call(p.ctx, uint64(p.handle))
	if err != nil {
		return 0, fmt.Errorf("vtwasm: program_generation: %w", err)
	}
	return uint32(res[0]), nil
}

func (p *Parser) Title() (string, error) {
	raw, err := p.readOut("vt_title", titleBufferBytes)
	return string(raw), err
}

func (p *Parser) TakeNotifications() ([]Notification, error) {
	raw, err := p.readOut("vt_take_notifications", notificationBufferBytes)
	if err != nil {
		return nil, err
	}
	var out []Notification
	for len(raw) > 0 {
		title, rest, ok := lengthPrefixed(raw)
		if !ok {
			return out, fmt.Errorf("vtwasm: truncated notification title")
		}
		body, rest, ok := lengthPrefixed(rest)
		if !ok {
			return out, fmt.Errorf("vtwasm: truncated notification body")
		}
		out = append(out, Notification{Title: string(title), Body: string(body)})
		raw = rest
	}
	return out, nil
}

func (p *Parser) SetCellPixels(width, height uint32) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if _, err := p.module.ExportedFunction("vt_set_cell_pixels").Call(p.ctx, uint64(p.handle), uint64(width), uint64(height)); err != nil {
		return fmt.Errorf("vtwasm: set_cell_pixels: %w", err)
	}
	return nil
}

func (p *Parser) SetDefaultColors(foreground, background int32) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if _, err := p.module.ExportedFunction("vt_set_default_colors").Call(p.ctx, uint64(p.handle), colorWord(foreground), colorWord(background)); err != nil {
		return fmt.Errorf("vtwasm: set_default_colors: %w", err)
	}
	return nil
}

func colorWord(rgb int32) uint64 {
	if rgb < 0 {
		return 0
	}
	return uint64(uint32(rgb)&0x00ff_ffff) | knownColor
}

func lengthPrefixed(raw []byte) ([]byte, []byte, bool) {
	if len(raw) < 4 {
		return nil, nil, false
	}
	n := binary.LittleEndian.Uint32(raw[:4])
	if uint64(len(raw)-4) < uint64(n) {
		return nil, nil, false
	}
	return raw[4 : 4+n], raw[4+n:], true
}

func (p *Parser) readOut(fn string, capacity uint32) ([]byte, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	res, err := p.module.ExportedFunction("vt_alloc").Call(p.ctx, uint64(capacity))
	if err != nil {
		return nil, fmt.Errorf("vtwasm: alloc %s buffer: %w", fn, err)
	}
	out := uint32(res[0])
	defer func() { _, _ = p.module.ExportedFunction("vt_free").Call(p.ctx, uint64(out), uint64(capacity)) }()
	res, err = p.module.ExportedFunction(fn).Call(p.ctx, uint64(p.handle), uint64(out), uint64(capacity))
	if err != nil {
		return nil, fmt.Errorf("vtwasm: %s: %w", fn, err)
	}
	switch written := uint32(res[0]); written {
	case 0:
		return nil, nil
	case renderErr, renderTooBig:
		return nil, fmt.Errorf("vtwasm: %s failed for handle %d", fn, p.handle)
	default:
		bytes, ok := p.module.Memory().Read(out, written)
		if !ok {
			return nil, fmt.Errorf("vtwasm: read %d bytes at %d out of range", written, out)
		}
		return append([]byte(nil), bytes...), nil
	}
}
