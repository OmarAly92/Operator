package tunnel

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"
)

type BinaryStore interface {
	Ensure(ctx context.Context, spec BinarySpec) (string, error)
}

type StoreDeps struct {
	Dir        string
	HTTPClient *http.Client
	LookPath   func(string) (string, error)
	Version    func(path string) (string, error)
	Log        *slog.Logger
}

type Store struct {
	dir      string
	client   *http.Client
	lookPath func(string) (string, error)
	version  func(string) (string, error)
	log      *slog.Logger
}

func NewStore(deps StoreDeps) *Store {
	client := deps.HTTPClient
	if client == nil {
		client = &http.Client{Timeout: 5 * time.Minute}
	}
	lookPath := deps.LookPath
	if lookPath == nil {
		lookPath = exec.LookPath
	}
	version := deps.Version
	if version == nil {
		version = binaryVersion
	}
	log := deps.Log
	if log == nil {
		log = slog.Default()
	}
	return &Store{dir: deps.Dir, client: client, lookPath: lookPath, version: version, log: log}
}

func (s *Store) Ensure(ctx context.Context, spec BinarySpec) (string, error) {
	if path, ok := s.fromPath(spec); ok {
		return path, nil
	}
	cached := s.cachedPath(spec)
	if _, err := os.Stat(cached); err == nil {
		return cached, nil
	}
	return s.download(ctx, spec, cached)
}

func (s *Store) fromPath(spec BinarySpec) (string, bool) {
	path, err := s.lookPath(spec.Name)
	if err != nil || path == "" {
		return "", false
	}
	if spec.MinVersion == "" {
		return path, true
	}
	found, err := s.version(path)
	if err != nil {
		return "", false
	}
	if compareVersions(found, spec.MinVersion) < 0 {
		return "", false
	}
	return path, true
}

func (s *Store) cachedPath(spec BinarySpec) string {
	name := spec.Name + "-" + spec.Version
	if runtime.GOOS == "windows" {
		name += ".exe"
	}
	return filepath.Join(s.dir, name)
}

func (s *Store) download(ctx context.Context, spec BinarySpec, dest string) (string, error) {
	url, err := spec.URL(runtime.GOOS, runtime.GOARCH)
	if err != nil {
		return "", err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, http.NoBody)
	if err != nil {
		return "", err
	}
	res, err := s.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("download %s: %w", spec.Name, err)
	}
	defer func() { _ = res.Body.Close() }()
	if res.StatusCode != http.StatusOK {
		return "", fmt.Errorf("download %s: %s returned %d", spec.Name, url, res.StatusCode)
	}
	archive, err := io.ReadAll(res.Body)
	if err != nil {
		return "", fmt.Errorf("download %s: %w", spec.Name, err)
	}
	if want := spec.SHA256[runtime.GOOS+"/"+runtime.GOARCH]; want != "" {
		sum := sha256.Sum256(archive)
		if got := hex.EncodeToString(sum[:]); got != want {
			return "", fmt.Errorf("download %s: checksum mismatch (got %s)", spec.Name, got)
		}
	}
	binary, err := extract(spec, archive)
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(s.dir, 0o700); err != nil {
		return "", err
	}
	tmp, err := os.CreateTemp(s.dir, "."+spec.Name+"-*.tmp")
	if err != nil {
		return "", err
	}
	tmpName := tmp.Name()
	defer func() { _ = os.Remove(tmpName) }()
	if _, err := tmp.Write(binary); err != nil {
		_ = tmp.Close()
		return "", err
	}
	if err := tmp.Chmod(0o755); err != nil {
		_ = tmp.Close()
		return "", err
	}
	if err := tmp.Close(); err != nil {
		return "", err
	}
	if err := os.Rename(tmpName, dest); err != nil {
		return "", err
	}
	if spec.MinVersion != "" {
		found, err := s.version(dest)
		if err != nil {
			return "", fmt.Errorf("verify %s: %w", spec.Name, err)
		}
		if compareVersions(found, spec.MinVersion) < 0 {
			return "", fmt.Errorf("verify %s: reported version %s is below %s", spec.Name, found, spec.MinVersion)
		}
	}
	return dest, nil
}

func extract(spec BinarySpec, archive []byte) ([]byte, error) {
	switch spec.Archive {
	case ArchiveZip:
		return extractZip(spec.EntryName, archive)
	case ArchiveTarGz:
		return extractTarGz(spec.EntryName, archive)
	default:
		return nil, fmt.Errorf("tunnel: unknown archive kind for %s", spec.Name)
	}
}

func extractZip(entry string, archive []byte) ([]byte, error) {
	reader, err := zip.NewReader(bytes.NewReader(archive), int64(len(archive)))
	if err != nil {
		return nil, err
	}
	for _, file := range reader.File {
		if filepath.Base(file.Name) != entry && filepath.Base(file.Name) != entry+".exe" {
			continue
		}
		rc, err := file.Open()
		if err != nil {
			return nil, err
		}
		data, readErr := io.ReadAll(io.LimitReader(rc, 200<<20))
		_ = rc.Close()
		if readErr != nil {
			return nil, readErr
		}
		return data, nil
	}
	return nil, fmt.Errorf("tunnel: %s not found in archive", entry)
}

func extractTarGz(entry string, archive []byte) ([]byte, error) {
	gz, err := gzip.NewReader(bytes.NewReader(archive))
	if err != nil {
		return nil, err
	}
	defer func() { _ = gz.Close() }()
	reader := tar.NewReader(gz)
	for {
		header, err := reader.Next()
		if errors.Is(err, io.EOF) {
			return nil, fmt.Errorf("tunnel: %s not found in archive", entry)
		}
		if err != nil {
			return nil, err
		}
		if header.Typeflag != tar.TypeReg {
			continue
		}
		if filepath.Base(header.Name) != entry && filepath.Base(header.Name) != entry+".exe" {
			continue
		}
		return io.ReadAll(io.LimitReader(reader, 200<<20))
	}
}

func binaryVersion(path string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, path, "--version").CombinedOutput()
	if err != nil {
		return "", err
	}
	return firstVersionToken(string(out)), nil
}

func firstVersionToken(text string) string {
	for _, field := range strings.Fields(text) {
		trimmed := strings.TrimPrefix(field, "v")
		if trimmed == "" || trimmed[0] < '0' || trimmed[0] > '9' {
			continue
		}
		if strings.Contains(trimmed, ".") {
			return strings.TrimSuffix(trimmed, ",")
		}
	}
	return ""
}

func compareVersions(a, b string) int {
	aParts, bParts := strings.Split(a, "."), strings.Split(b, ".")
	for i := 0; i < len(aParts) || i < len(bParts); i++ {
		var x, y int
		if i < len(aParts) {
			x, _ = strconv.Atoi(numericPrefix(aParts[i]))
		}
		if i < len(bParts) {
			y, _ = strconv.Atoi(numericPrefix(bParts[i]))
		}
		if x != y {
			if x < y {
				return -1
			}
			return 1
		}
	}
	return 0
}

func numericPrefix(part string) string {
	end := 0
	for end < len(part) && part[end] >= '0' && part[end] <= '9' {
		end++
	}
	return part[:end]
}
