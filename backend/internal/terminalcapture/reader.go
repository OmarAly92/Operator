package terminalcapture

import (
	"encoding/json"
	"errors"
	"io"
	"io/fs"
	"os"
	"path/filepath"
)

type CaptureCursor struct {
	Epoch   string
	Segment uint64
	Offset  int64
}

func (c CaptureCursor) ByteOffset() int64 {
	if c.Segment <= FirstSequence {
		return c.Offset
	}
	return int64(c.Segment-FirstSequence)*SegmentSize + c.Offset
}

func CursorAtOffset(epoch string, off int64) CaptureCursor {
	if off < 0 {
		off = 0
	}
	return CaptureCursor{
		Epoch:   epoch,
		Segment: uint64(off/SegmentSize) + FirstSequence,
		Offset:  off % SegmentSize,
	}
}

type Reader struct {
	dir   string
	epoch string
}

func NewReader(dir string) *Reader {
	return &Reader{dir: dir, epoch: filepath.Base(dir)}
}

func (r *Reader) Epoch() string { return r.epoch }

type ReadResult struct {
	Data     []byte
	Cursor   CaptureCursor
	Gap      *CaptureCursor
	Sealed   bool
	Manifest *Manifest
}

func (r *Reader) Read(from CaptureCursor) (ReadResult, error) {
	if from.Segment < FirstSequence {
		from.Segment = FirstSequence
		from.Offset = 0
	}
	from.Epoch = r.epoch

	manifest, sealed, err := r.readManifest()
	if err != nil {
		return ReadResult{}, err
	}
	retained, err := r.retainedFloor(manifest)
	if err != nil {
		return ReadResult{}, err
	}

	res := ReadResult{Cursor: from, Sealed: sealed, Manifest: manifest}

	if from.Segment < retained {
		gap := CaptureCursor{Epoch: r.epoch, Segment: retained, Offset: 0}
		res.Gap = &gap
		return res, nil
	}

	cur := from
	for {
		path, active, ok := r.resolveSegment(cur.Segment)
		if !ok {
			break
		}
		chunk, err := readSegmentFrom(path, cur.Offset)
		if err != nil {
			return ReadResult{}, err
		}
		res.Data = append(res.Data, chunk...)
		cur.Offset += int64(len(chunk))
		if active {
			break
		}
		if cur.Offset < SegmentSize {
			break
		}
		cur.Segment++
		cur.Offset = 0
	}
	res.Cursor = cur
	return res, nil
}

func (r *Reader) resolveSegment(seq uint64) (path string, active bool, ok bool) {
	ready := filepath.Join(r.dir, SegmentName(seq, ReadySuffix))
	if _, err := os.Stat(ready); err == nil {
		return ready, false, true
	}
	open := filepath.Join(r.dir, SegmentName(seq, OpenSuffix))
	if _, err := os.Stat(open); err == nil {
		return open, true, true
	}
	return "", false, false
}

func (r *Reader) readManifest() (*Manifest, bool, error) {
	raw, err := os.ReadFile(filepath.Join(r.dir, ManifestFileName))
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return nil, false, nil
		}
		return nil, false, err
	}
	var m Manifest
	if err := json.Unmarshal(raw, &m); err != nil {
		return nil, false, err
	}
	return &m, true, nil
}

func (r *Reader) retainedFloor(manifest *Manifest) (uint64, error) {
	floor := uint64(FirstSequence)
	if manifest != nil && manifest.FirstRetainedSequence > floor {
		floor = manifest.FirstRetainedSequence
	}
	raw, err := os.ReadFile(filepath.Join(r.dir, GapFileName))
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return floor, nil
		}
		return 0, err
	}
	var g Gap
	if err := json.Unmarshal(raw, &g); err != nil {
		return 0, err
	}
	if g.FirstRetainedSequence > floor {
		floor = g.FirstRetainedSequence
	}
	return floor, nil
}

func readSegmentFrom(path string, offset int64) ([]byte, error) {
	f, err := os.Open(path)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return nil, nil
		}
		return nil, err
	}
	defer f.Close()
	if offset > 0 {
		if _, err := f.Seek(offset, io.SeekStart); err != nil {
			return nil, err
		}
	}
	return io.ReadAll(f)
}
