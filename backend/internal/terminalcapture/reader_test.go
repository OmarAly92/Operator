package terminalcapture

import (
	"bytes"
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"time"
)

func writeSegment(t *testing.T, dir string, seq uint64, suffix string, data []byte, mtime time.Time) string {
	t.Helper()
	p := filepath.Join(dir, SegmentName(seq, suffix))
	if err := os.WriteFile(p, data, 0o600); err != nil {
		t.Fatalf("write segment %d: %v", seq, err)
	}
	if !mtime.IsZero() {
		if err := os.Chtimes(p, mtime, mtime); err != nil {
			t.Fatalf("chtimes %d: %v", seq, err)
		}
	}
	return p
}

func fullSegment(b byte) []byte {
	d := make([]byte, SegmentSize)
	for i := range d {
		d[i] = b
	}
	return d
}

func TestReaderOrdersBySequenceNotMtime(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "11111111-2222-3333-4444-555555555555")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	writeSegment(t, dir, 1, ReadySuffix, fullSegment('A'), now)
	writeSegment(t, dir, 2, ReadySuffix, fullSegment('B'), now.Add(-time.Hour))
	writeSegment(t, dir, 3, ReadySuffix, []byte("CCC-tail"), now.Add(-2*time.Hour))

	r := NewReader(dir)
	res, err := r.Read(CaptureCursor{Segment: FirstSequence})
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	want := append(append(fullSegment('A'), fullSegment('B')...), []byte("CCC-tail")...)
	if !bytes.Equal(res.Data, want) {
		t.Fatalf("data mismatch: len got=%d want=%d; head=%q tail=%q", len(res.Data), len(want), res.Data[:4], res.Data[len(res.Data)-8:])
	}
	if res.Cursor.Segment != 3 || res.Cursor.Offset != int64(len("CCC-tail")) {
		t.Fatalf("cursor = %+v, want segment 3 offset 8", res.Cursor)
	}
}

func TestReaderResumesFromCursorMidStream(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "epoch-x")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	writeSegment(t, dir, 1, ReadySuffix, fullSegment('A'), time.Time{})
	writeSegment(t, dir, 2, OpenSuffix, []byte("live-bytes"), time.Time{})

	r := NewReader(dir)
	res, err := r.Read(CaptureCursor{Segment: 2, Offset: 5})
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if string(res.Data) != "bytes" {
		t.Fatalf("data = %q, want %q", res.Data, "bytes")
	}
	if res.Cursor.Segment != 2 || res.Cursor.Offset != 10 {
		t.Fatalf("cursor = %+v, want segment 2 offset 10", res.Cursor)
	}
	if res.Sealed {
		t.Fatalf("no manifest present, Sealed must be false")
	}
}

func TestReaderSurfacesGapAtFirstRetainedSequence(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "epoch-gap")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	writeSegment(t, dir, 4, ReadySuffix, []byte("segment-four"), time.Time{})
	if err := atomicWriteJSON(dir, GapFileName, Gap{Epoch: "epoch-gap", FirstRetainedSequence: 4}); err != nil {
		t.Fatal(err)
	}

	r := NewReader(dir)
	res, err := r.Read(CaptureCursor{Segment: 1})
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if res.Gap == nil {
		t.Fatal("expected a gap")
	}
	if res.Gap.Segment != 4 || res.Gap.Offset != 0 {
		t.Fatalf("gap cursor = %+v, want segment 4 offset 0", *res.Gap)
	}
	if len(res.Data) != 0 {
		t.Fatalf("gap read must carry no data, got %d bytes", len(res.Data))
	}

	res, err = r.Read(*res.Gap)
	if err != nil {
		t.Fatalf("read after gap: %v", err)
	}
	if string(res.Data) != "segment-four" {
		t.Fatalf("post-gap data = %q", res.Data)
	}
}

func TestReaderReportsSealedWhenManifestPresent(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "epoch-seal")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	writeSegment(t, dir, 1, ReadySuffix, []byte("done"), time.Time{})
	if err := atomicWriteJSON(dir, ManifestFileName, Manifest{Epoch: "epoch-seal", FinalSequence: 1, TotalBytes: 4, FirstRetainedSequence: 1}); err != nil {
		t.Fatal(err)
	}
	r := NewReader(dir)
	res, err := r.Read(CaptureCursor{Segment: 1})
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if !res.Sealed || res.Manifest == nil || res.Manifest.FinalSequence != 1 {
		t.Fatalf("sealed=%v manifest=%+v", res.Sealed, res.Manifest)
	}
}

func TestReaderNeverMutatesSegments(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "epoch-ro")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	paths := []string{
		writeSegment(t, dir, 1, ReadySuffix, fullSegment('A'), time.Time{}),
		writeSegment(t, dir, 2, ReadySuffix, []byte("second"), time.Time{}),
		writeSegment(t, dir, 3, OpenSuffix, []byte("third-open"), time.Time{}),
	}
	type snap struct {
		ino  uint64
		size int64
		mod  time.Time
	}
	take := func() map[string]snap {
		m := map[string]snap{}
		for _, p := range paths {
			fi, err := os.Stat(p)
			if err != nil {
				t.Fatalf("stat %s: %v", p, err)
			}
			st := fi.Sys().(*syscall.Stat_t)
			m[p] = snap{ino: st.Ino, size: fi.Size(), mod: fi.ModTime()}
		}
		return m
	}
	before := take()

	r := NewReader(dir)
	cur := CaptureCursor{Segment: FirstSequence}
	for i := 0; i < 3; i++ {
		res, err := r.Read(cur)
		if err != nil {
			t.Fatalf("read: %v", err)
		}
		cur = res.Cursor
	}

	after := take()
	for p, b := range before {
		a := after[p]
		if a != b {
			t.Fatalf("segment %s changed after read: before=%+v after=%+v", p, b, a)
		}
	}
	entries, _ := os.ReadDir(dir)
	if len(entries) != 3 {
		t.Fatalf("reader created or removed files: dir now has %d entries", len(entries))
	}
}

func TestCursorByteOffsetRoundTrips(t *testing.T) {
	cases := []int64{0, 1, SegmentSize - 1, SegmentSize, SegmentSize + 7, 9 * SegmentSize}
	for _, off := range cases {
		c := CursorAtOffset("e", off)
		if got := c.ByteOffset(); got != off {
			t.Fatalf("offset %d -> cursor %+v -> %d", off, c, got)
		}
	}
}
