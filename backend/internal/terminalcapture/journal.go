package terminalcapture

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
)

const (
	SegmentSize       = 1 << 20
	MaxSealedSegments = 8
	FirstSequence     = 1

	OpenSuffix       = ".open"
	ReadySuffix      = ".ready"
	GapFileName      = "gap.json"
	ManifestFileName = "manifest.json"

	sequenceDigits = 20
)

type Manifest struct {
	Epoch                 string `json:"epoch"`
	FinalSequence         uint64 `json:"finalSequence"`
	TotalBytes            int64  `json:"totalBytes"`
	FirstRetainedSequence uint64 `json:"firstRetainedSequence"`
}

type Gap struct {
	Epoch                 string `json:"epoch"`
	FirstRetainedSequence uint64 `json:"firstRetainedSequence"`
}

func SegmentName(seq uint64, suffix string) string {
	return fmt.Sprintf("%0*d%s", sequenceDigits, seq, suffix)
}

func CaptureRoot(dataDir string) string {
	return filepath.Join(dataDir, "terminal-capture")
}

type Journal struct {
	dir           string
	epoch         string
	seq           uint64
	active        *os.File
	activeSize    int
	totalBytes    int64
	firstRetained uint64
	closed        bool
}

func Open(dir string) (*Journal, error) {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, err
	}
	j := &Journal{
		dir:           dir,
		epoch:         filepath.Base(dir),
		seq:           FirstSequence,
		firstRetained: FirstSequence,
	}
	if err := j.openActive(); err != nil {
		return nil, err
	}
	return j, nil
}

func (j *Journal) Write(p []byte) (int, error) {
	if j.closed {
		return 0, errors.New("terminalcapture: write after close")
	}
	written := 0
	for len(p) > 0 {
		space := SegmentSize - j.activeSize
		n := len(p)
		if n > space {
			n = space
		}
		m, err := j.active.Write(p[:n])
		j.activeSize += m
		j.totalBytes += int64(m)
		written += m
		if err != nil {
			return written, err
		}
		p = p[n:]
		if j.activeSize >= SegmentSize {
			if err := j.rotate(); err != nil {
				return written, err
			}
		}
	}
	return written, nil
}

func (j *Journal) Close() error {
	if j.closed {
		return nil
	}
	j.closed = true

	var finalSeq uint64
	if j.activeSize > 0 {
		if err := j.sealActive(); err != nil {
			return err
		}
		finalSeq = j.seq
		if err := j.pruneSealed(finalSeq); err != nil {
			return err
		}
	} else {
		if j.active != nil {
			_ = j.active.Close()
			j.active = nil
			_ = os.Remove(filepath.Join(j.dir, SegmentName(j.seq, OpenSuffix)))
		}
		if j.seq > j.firstRetained {
			finalSeq = j.seq - 1
		}
	}

	return atomicWriteJSON(j.dir, ManifestFileName, Manifest{
		Epoch:                 j.epoch,
		FinalSequence:         finalSeq,
		TotalBytes:            j.totalBytes,
		FirstRetainedSequence: j.firstRetained,
	})
}

func (j *Journal) openActive() error {
	f, err := os.OpenFile(
		filepath.Join(j.dir, SegmentName(j.seq, OpenSuffix)),
		os.O_CREATE|os.O_WRONLY|os.O_TRUNC,
		0o600,
	)
	if err != nil {
		return err
	}
	j.active = f
	j.activeSize = 0
	return nil
}

func (j *Journal) sealActive() error {
	if err := j.active.Sync(); err != nil {
		return err
	}
	if err := j.active.Close(); err != nil {
		return err
	}
	j.active = nil
	from := filepath.Join(j.dir, SegmentName(j.seq, OpenSuffix))
	to := filepath.Join(j.dir, SegmentName(j.seq, ReadySuffix))
	return os.Rename(from, to)
}

func (j *Journal) rotate() error {
	if err := j.sealActive(); err != nil {
		return err
	}
	if err := j.pruneSealed(j.seq); err != nil {
		return err
	}
	j.seq++
	return j.openActive()
}

func (j *Journal) pruneSealed(highestSealed uint64) error {
	for highestSealed-j.firstRetained+1 > MaxSealedSegments {
		newFirst := j.firstRetained + 1
		if err := atomicWriteJSON(j.dir, GapFileName, Gap{
			Epoch:                 j.epoch,
			FirstRetainedSequence: newFirst,
		}); err != nil {
			return err
		}
		victim := filepath.Join(j.dir, SegmentName(j.firstRetained, ReadySuffix))
		if err := os.Remove(victim); err != nil && !errors.Is(err, fs.ErrNotExist) {
			return err
		}
		j.firstRetained = newFirst
	}
	return nil
}

func atomicWriteJSON(dir, name string, v any) error {
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, name+".tmp-*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		_ = os.Remove(tmpName)
		return err
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		_ = os.Remove(tmpName)
		return err
	}
	if err := tmp.Close(); err != nil {
		_ = os.Remove(tmpName)
		return err
	}
	return os.Rename(tmpName, filepath.Join(dir, name))
}
