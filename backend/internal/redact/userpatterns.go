package redact

import (
	"bufio"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// userPatternsFile is read from the daemon's data dir, which resolves under
// ~/.operator. Operator writes no app state anywhere else.
const userPatternsFile = "redact-patterns.txt"

// maxUserPatterns bounds how many extra expressions are installed. Every
// pattern runs over every block's text on the hook path, so an unbounded file
// would be a way to make the daemon slow by editing a text file.
const maxUserPatterns = 64

// maxUserPatternsBytes bounds the file itself, so a stray huge file is not read
// into memory line by line before the count cap can apply.
const maxUserPatternsBytes = 64 << 10

// LoadUserPatterns merges the user's own secret shapes after the built-in set
// and returns how many were installed. A missing or unreadable file leaves the
// defaults in place: redaction degrading to the defaults is acceptable, and
// refusing to boot over a typo in an optional file is not.
//
// It mutates package state and must be called once, at start, before any text
// is redacted.
func LoadUserPatterns(dataDir string, log *slog.Logger) int {
	if strings.TrimSpace(dataDir) == "" {
		return 0
	}
	path := filepath.Join(dataDir, userPatternsFile)
	info, err := os.Stat(path)
	if err != nil || info.IsDir() || info.Size() > maxUserPatternsBytes {
		return 0
	}
	file, err := os.Open(path)
	if err != nil {
		return 0
	}
	defer func() { _ = file.Close() }()

	installed := 0
	scanner := bufio.NewScanner(file)
	for scanner.Scan() && installed < maxUserPatterns {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		re, err := regexp.Compile(line)
		if err != nil {
			if log != nil {
				log.Warn("skipping invalid redaction pattern", "file", path, "pattern", line, "error", err)
			}
			continue
		}
		patterns = append(patterns, re)
		installed++
	}
	return installed
}
