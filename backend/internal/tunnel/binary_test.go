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
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func zipped(t *testing.T, name string, content []byte) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	w, err := zw.Create(name)
	if err != nil {
		t.Fatalf("zip create: %v", err)
	}
	if _, err := w.Write(content); err != nil {
		t.Fatalf("zip write: %v", err)
	}
	if err := zw.Close(); err != nil {
		t.Fatalf("zip close: %v", err)
	}
	return buf.Bytes()
}

func tarred(t *testing.T, name string, content []byte) []byte {
	t.Helper()
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	if err := tw.WriteHeader(&tar.Header{Name: name, Mode: 0o755, Size: int64(len(content))}); err != nil {
		t.Fatalf("tar header: %v", err)
	}
	if _, err := tw.Write(content); err != nil {
		t.Fatalf("tar write: %v", err)
	}
	if err := tw.Close(); err != nil {
		t.Fatalf("tar close: %v", err)
	}
	if err := gz.Close(); err != nil {
		t.Fatalf("gzip close: %v", err)
	}
	return buf.Bytes()
}

func TestStorePrefersBinaryOnPath(t *testing.T) {
	store := NewStore(StoreDeps{
		Dir:      t.TempDir(),
		LookPath: func(string) (string, error) { return "/opt/homebrew/bin/ngrok", nil },
		Version:  func(string) (string, error) { return "3.39.6", nil },
	})

	got, err := store.Ensure(context.Background(), NgrokProvider(NgrokConfig{}).Binary())
	if err != nil {
		t.Fatalf("Ensure: %v", err)
	}
	if got != "/opt/homebrew/bin/ngrok" {
		t.Errorf("got %q, want the PATH binary", got)
	}
}

func TestStoreRejectsPathBinaryBelowMinVersion(t *testing.T) {
	payload := []byte("fake-ngrok")
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write(zipped(t, "ngrok", payload))
	}))
	defer srv.Close()

	spec := NgrokProvider(NgrokConfig{}).Binary()
	spec.URL = func(string, string) (string, error) { return srv.URL, nil }

	store := NewStore(StoreDeps{
		Dir:      t.TempDir(),
		LookPath: func(string) (string, error) { return "/usr/local/bin/ngrok", nil },
		Version: func(path string) (string, error) {
			if path == "/usr/local/bin/ngrok" {
				return "2.3.40", nil
			}
			return "3.39.6", nil
		},
	})

	got, err := store.Ensure(context.Background(), spec)
	if err != nil {
		t.Fatalf("Ensure: %v", err)
	}
	if got == "/usr/local/bin/ngrok" {
		t.Fatal("a PATH binary below MinVersion must not be used")
	}
	if body, readErr := os.ReadFile(got); readErr != nil || !bytes.Equal(body, payload) {
		t.Fatalf("downloaded binary content = %q, %v", body, readErr)
	}
}

func TestStoreDownloadsAndExtractsZip(t *testing.T) {
	payload := []byte("fake-ngrok-binary")
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write(zipped(t, "ngrok", payload))
	}))
	defer srv.Close()

	dir := t.TempDir()
	spec := NgrokProvider(NgrokConfig{}).Binary()
	spec.URL = func(string, string) (string, error) { return srv.URL, nil }

	store := NewStore(StoreDeps{
		Dir:      dir,
		LookPath: func(string) (string, error) { return "", errors.New("not found") },
		Version:  func(string) (string, error) { return "3.39.6", nil },
	})

	got, err := store.Ensure(context.Background(), spec)
	if err != nil {
		t.Fatalf("Ensure: %v", err)
	}
	if filepath.Dir(got) != dir {
		t.Errorf("binary landed in %q, want under %q", got, dir)
	}
	info, err := os.Stat(got)
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	if runtime.GOOS != "windows" && info.Mode().Perm() != 0o755 {
		t.Errorf("mode = %v, want 0755", info.Mode().Perm())
	}
}

func TestStoreDownloadsAndExtractsTarGzVerifyingChecksum(t *testing.T) {
	payload := []byte("fake-cloudflared-binary")
	archive := tarred(t, "cloudflared", payload)
	sum := sha256.Sum256(archive)

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write(archive)
	}))
	defer srv.Close()

	spec := CloudflaredProvider().Binary()
	spec.Archive = ArchiveTarGz
	spec.URL = func(string, string) (string, error) { return srv.URL, nil }
	spec.SHA256 = map[string]string{runtime.GOOS + "/" + runtime.GOARCH: hex.EncodeToString(sum[:])}

	store := NewStore(StoreDeps{
		Dir:      t.TempDir(),
		LookPath: func(string) (string, error) { return "", errors.New("not found") },
		Version:  func(string) (string, error) { return cloudflaredVersion, nil },
	})

	got, err := store.Ensure(context.Background(), spec)
	if err != nil {
		t.Fatalf("Ensure: %v", err)
	}
	if body, readErr := os.ReadFile(got); readErr != nil || !bytes.Equal(body, payload) {
		t.Fatalf("extracted content = %q, %v", body, readErr)
	}
}

func TestStoreRejectsAnOldPathCloudflaredInFavourOfThePinnedCopy(t *testing.T) {
	payload := []byte("pinned-cloudflared")
	archive := tarred(t, "cloudflared", payload)
	sum := sha256.Sum256(archive)

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write(archive)
	}))
	defer srv.Close()

	spec := CloudflaredProvider().Binary()
	spec.Archive = ArchiveTarGz
	spec.URL = func(string, string) (string, error) { return srv.URL, nil }
	spec.SHA256 = map[string]string{runtime.GOOS + "/" + runtime.GOARCH: hex.EncodeToString(sum[:])}

	store := NewStore(StoreDeps{
		Dir:      t.TempDir(),
		LookPath: func(string) (string, error) { return "/usr/local/bin/cloudflared", nil },
		Version: func(path string) (string, error) {
			if path == "/usr/local/bin/cloudflared" {
				return "2023.8.2", nil
			}
			return cloudflaredVersion, nil
		},
	})

	got, err := store.Ensure(context.Background(), spec)
	if err != nil {
		t.Fatalf("Ensure: %v", err)
	}
	if got == "/usr/local/bin/cloudflared" {
		t.Fatal("a PATH cloudflared older than the pinned, checksummed release must not be preferred over it")
	}
	if body, readErr := os.ReadFile(got); readErr != nil || !bytes.Equal(body, payload) {
		t.Fatalf("downloaded binary content = %q, %v", body, readErr)
	}
}

func TestCloudflaredVersionOutputParsesToThePinnedVersion(t *testing.T) {
	sample := "cloudflared version " + cloudflaredVersion + " (built 2026-03-01-1200 UTC)"
	if got := firstVersionToken(sample); got != cloudflaredVersion {
		t.Fatalf("firstVersionToken(%q) = %q, want %q", sample, got, cloudflaredVersion)
	}
	if compareVersions(firstVersionToken(sample), CloudflaredProvider().Binary().MinVersion) < 0 {
		t.Fatal("the pinned cloudflared must satisfy its own MinVersion")
	}
}

func TestStoreRejectsChecksumMismatch(t *testing.T) {
	archive := tarred(t, "cloudflared", []byte("tampered"))
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write(archive)
	}))
	defer srv.Close()

	spec := CloudflaredProvider().Binary()
	spec.URL = func(string, string) (string, error) { return srv.URL, nil }
	spec.SHA256 = map[string]string{
		runtime.GOOS + "/" + runtime.GOARCH: "0000000000000000000000000000000000000000000000000000000000000000",
	}

	store := NewStore(StoreDeps{
		Dir:      t.TempDir(),
		LookPath: func(string) (string, error) { return "", errors.New("not found") },
	})

	if _, err := store.Ensure(context.Background(), spec); err == nil {
		t.Fatal("want an error on checksum mismatch")
	}
}

func TestStoreReusesCachedBinaryWithoutDownloading(t *testing.T) {
	payload := []byte("fake-ngrok")
	var hits int
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits++
		_, _ = w.Write(zipped(t, "ngrok", payload))
	}))
	defer srv.Close()

	spec := NgrokProvider(NgrokConfig{}).Binary()
	spec.URL = func(string, string) (string, error) { return srv.URL, nil }

	store := NewStore(StoreDeps{
		Dir:      t.TempDir(),
		LookPath: func(string) (string, error) { return "", errors.New("not found") },
		Version:  func(string) (string, error) { return "3.39.6", nil },
	})

	for i := 0; i < 2; i++ {
		if _, err := store.Ensure(context.Background(), spec); err != nil {
			t.Fatalf("Ensure %d: %v", i, err)
		}
	}
	if hits != 1 {
		t.Errorf("downloaded %d times, want 1", hits)
	}
}
