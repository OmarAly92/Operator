package terminalcapture

import (
	"encoding/binary"
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

func epochDir(t *testing.T) string {
	t.Helper()
	return filepath.Join(t.TempDir(), "11111111-2222-3333-4444-555555555555")
}

func dirBytes(t *testing.T, dir string) int64 {
	t.Helper()
	var total int64
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("read dir: %v", err)
	}
	for _, e := range entries {
		info, err := e.Info()
		if err != nil {
			t.Fatalf("stat %s: %v", e.Name(), err)
		}
		total += info.Size()
	}
	return total
}

func highestSegment(t *testing.T, dir string) (string, []byte) {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("read dir: %v", err)
	}
	best := ""
	bestSeq := int64(-1)
	for _, e := range entries {
		name := e.Name()
		var raw string
		switch {
		case strings.HasSuffix(name, OpenSuffix):
			raw = strings.TrimSuffix(name, OpenSuffix)
		case strings.HasSuffix(name, ReadySuffix):
			raw = strings.TrimSuffix(name, ReadySuffix)
		default:
			continue
		}
		seq, err := strconv.ParseInt(raw, 10, 64)
		if err != nil {
			continue
		}
		if seq > bestSeq {
			bestSeq = seq
			best = name
		}
	}
	if best == "" {
		t.Fatalf("no segment files in %s", dir)
	}
	data, err := os.ReadFile(filepath.Join(dir, best))
	if err != nil {
		t.Fatalf("read %s: %v", best, err)
	}
	return best, data
}

func TestJournalStaysBoundedWithoutReader(t *testing.T) {
	dir := epochDir(t)
	j, err := Open(dir)
	if err != nil {
		t.Fatalf("open: %v", err)
	}

	filler := make([]byte, 64<<10)
	for i := range filler {
		filler[i] = 'a'
	}
	written := 0
	target := 12 << 20
	for written < target {
		n, err := j.Write(filler)
		if err != nil {
			t.Fatalf("write after %d bytes: %v", written, err)
		}
		if n != len(filler) {
			t.Fatalf("short write: %d != %d", n, len(filler))
		}
		written += n
	}
	sentinel := []byte("SENTINEL-FINAL-BYTES-0xDEADBEEF")
	if _, err := j.Write(sentinel); err != nil {
		t.Fatalf("sentinel write: %v", err)
	}

	onDisk := dirBytes(t, dir)
	bound := int64(9<<20) + 64<<10
	if onDisk > bound {
		t.Fatalf("on-disk bytes %d exceed bound %d", onDisk, bound)
	}

	gapPath := filepath.Join(dir, GapFileName)
	raw, err := os.ReadFile(gapPath)
	if err != nil {
		t.Fatalf("gap.json missing: %v", err)
	}
	var gap Gap
	if err := json.Unmarshal(raw, &gap); err != nil {
		t.Fatalf("gap.json parse: %v", err)
	}
	if gap.FirstRetainedSequence < FirstSequence+1 {
		t.Fatalf("gap.json first retained %d not advanced past base", gap.FirstRetainedSequence)
	}

	name, data := highestSegment(t, dir)
	if !strings.Contains(string(data), string(sentinel)) {
		t.Fatalf("newest segment %s does not contain the final sentinel", name)
	}

	if err := j.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}
}

func TestJournalConcurrentReaderOrderedNoDuplicates(t *testing.T) {
	dir := epochDir(t)
	j, err := Open(dir)
	if err != nil {
		t.Fatalf("open: %v", err)
	}

	const totalSegments = 20
	perSegment := SegmentSize / 8

	done := make(chan struct{})
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		buf := make([]byte, 32<<10)
		var counter uint64
		bytesSinceYield := 0
		for counter < uint64(totalSegments*perSegment) {
			for off := 0; off < len(buf); off += 8 {
				binary.LittleEndian.PutUint64(buf[off:], counter)
				counter++
			}
			if _, err := j.Write(buf); err != nil {
				t.Errorf("write: %v", err)
				return
			}
			bytesSinceYield += len(buf)
			if bytesSinceYield >= 256<<10 {
				bytesSinceYield = 0
				time.Sleep(300 * time.Microsecond)
			}
		}
		if err := j.Close(); err != nil {
			t.Errorf("close: %v", err)
		}
		close(done)
	}()

	type seg struct {
		seq  uint64
		data []byte
	}
	var collected []seg
	gapObserved := false

	readOne := func(seq uint64) ([]byte, bool) {
		p := filepath.Join(dir, SegmentName(seq, ReadySuffix))
		data, err := os.ReadFile(p)
		if err != nil {
			return nil, false
		}
		return data, true
	}

	expected := uint64(FirstSequence)
	finished := false
	for !finished {
		data, ok := readOne(expected)
		if ok {
			collected = append(collected, seg{seq: expected, data: data})
			expected++
			continue
		}
		gapRaw, gapErr := os.ReadFile(filepath.Join(dir, GapFileName))
		if gapErr == nil {
			var gap Gap
			if err := json.Unmarshal(gapRaw, &gap); err == nil && gap.FirstRetainedSequence > expected {
				expected = gap.FirstRetainedSequence
				gapObserved = true
				continue
			}
		}
		select {
		case <-done:
			if _, ok := readOne(expected); !ok {
				finished = true
			}
		default:
			time.Sleep(200 * time.Microsecond)
		}
	}
	wg.Wait()

	if len(collected) < 2 {
		t.Fatalf("reader observed only %d segments", len(collected))
	}
	seen := map[uint64]bool{}
	var prevSeq uint64
	for i, s := range collected {
		if seen[s.seq] {
			t.Fatalf("duplicate segment sequence %d", s.seq)
		}
		seen[s.seq] = true
		if i > 0 && s.seq <= prevSeq {
			t.Fatalf("segments out of order: %d after %d", s.seq, prevSeq)
		}
		if i > 0 && s.seq != prevSeq+1 && !gapObserved {
			t.Fatalf("sequence jump %d -> %d with no recorded gap", prevSeq, s.seq)
		}
		prevSeq = s.seq
		base := (s.seq - FirstSequence) * uint64(perSegment)
		if len(s.data) != SegmentSize {
			t.Fatalf("segment %d size %d != %d", s.seq, len(s.data), SegmentSize)
		}
		for k := 0; k < perSegment; k++ {
			got := binary.LittleEndian.Uint64(s.data[k*8:])
			if got != base+uint64(k) {
				t.Fatalf("segment %d offset %d = %d, want %d", s.seq, k, got, base+uint64(k))
			}
		}
	}
}

func TestJournalShortSegmentSealedOnClose(t *testing.T) {
	dir := epochDir(t)
	j, err := Open(dir)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	payload := []byte("hello short segment, well under one mebibyte")
	if _, err := j.Write(payload); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := j.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("read dir: %v", err)
	}
	var ready []string
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), OpenSuffix) {
			t.Fatalf("open segment %s survived Close", e.Name())
		}
		if strings.HasSuffix(e.Name(), ReadySuffix) {
			ready = append(ready, e.Name())
		}
	}
	if len(ready) != 1 {
		t.Fatalf("want exactly one sealed segment, got %v", ready)
	}
	got, err := os.ReadFile(filepath.Join(dir, ready[0]))
	if err != nil {
		t.Fatalf("read sealed: %v", err)
	}
	if string(got) != string(payload) {
		t.Fatalf("sealed content %q != %q", got, payload)
	}

	raw, err := os.ReadFile(filepath.Join(dir, ManifestFileName))
	if err != nil {
		t.Fatalf("manifest missing: %v", err)
	}
	var m Manifest
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatalf("manifest parse: %v", err)
	}
	if m.FinalSequence != FirstSequence {
		t.Fatalf("manifest final sequence %d != %d", m.FinalSequence, FirstSequence)
	}
	if m.TotalBytes != int64(len(payload)) {
		t.Fatalf("manifest total bytes %d != %d", m.TotalBytes, len(payload))
	}
}

func TestJournalEmptyFinalSegmentNotSealed(t *testing.T) {
	dir := epochDir(t)
	j, err := Open(dir)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	full := make([]byte, SegmentSize)
	if _, err := j.Write(full); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := j.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("read dir: %v", err)
	}
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), OpenSuffix) {
			t.Fatalf("zero-byte open segment %s left behind", e.Name())
		}
		if strings.HasSuffix(e.Name(), ReadySuffix) {
			info, _ := e.Info()
			if info.Size() == 0 {
				t.Fatalf("zero-byte ready segment %s created", e.Name())
			}
		}
	}
	raw, err := os.ReadFile(filepath.Join(dir, ManifestFileName))
	if err != nil {
		t.Fatalf("manifest missing: %v", err)
	}
	var m Manifest
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatalf("manifest parse: %v", err)
	}
	if m.FinalSequence != FirstSequence {
		t.Fatalf("manifest final sequence %d != %d", m.FinalSequence, FirstSequence)
	}
}
