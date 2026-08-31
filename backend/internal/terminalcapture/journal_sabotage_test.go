package terminalcapture

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestReaderSideRotationLosesBytes(t *testing.T) {
	dir := epochDir(t)
	j, err := Open(dir)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer j.Close()

	if _, err := j.Write([]byte("before hijack ")); err != nil {
		t.Fatalf("write: %v", err)
	}

	activePath := filepath.Join(dir, SegmentName(FirstSequence, OpenSuffix))
	hijacked := filepath.Join(dir, "reader-stole-this")
	if err := os.Rename(activePath, hijacked); err != nil {
		t.Fatalf("reader-side rename: %v", err)
	}

	sentinel := "AFTER-HIJACK-SENTINEL"
	if _, err := j.Write([]byte(sentinel)); err != nil {
		t.Fatalf("write after hijack: %v", err)
	}

	visibleToReader := false
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		name := e.Name()
		if !strings.HasSuffix(name, OpenSuffix) && !strings.HasSuffix(name, ReadySuffix) {
			continue
		}
		data, _ := os.ReadFile(filepath.Join(dir, name))
		if strings.Contains(string(data), sentinel) {
			visibleToReader = true
		}
	}

	if visibleToReader {
		t.Fatal("expected reader-side rename to strand post-rename bytes on the unlinked inode")
	}

	stranded, err := os.ReadFile(hijacked)
	if err != nil {
		t.Fatalf("read hijacked inode: %v", err)
	}
	if !strings.Contains(string(stranded), sentinel) {
		t.Fatalf("post-rename bytes not found on the stranded inode either: %q", stranded)
	}
}
