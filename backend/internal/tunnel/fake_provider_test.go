package tunnel

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"testing"
)

type fakeProvider struct {
	name     string
	header   string
	binary   string
	mu       sync.Mutex
	url      string
	urlErr   error
	ready    bool
	healthy  bool
	failure  Failure
	urlCalls int
}

func newFakeProvider(t *testing.T, name string, script string) *fakeProvider {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, name)
	if runtime.GOOS == "windows" {
		t.Skip("fake shell-script binaries are not portable to Windows")
	}
	if err := os.WriteFile(path, []byte(script), 0o755); err != nil {
		t.Fatalf("write fake binary: %v", err)
	}
	return &fakeProvider{
		name:    name,
		header:  "X-Forwarded-For",
		binary:  path,
		url:     "https://fake-" + name + ".example",
		ready:   true,
		healthy: true,
	}
}

func (f *fakeProvider) setURL(url string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.url = url
}

func (f *fakeProvider) setHealthy(ok bool) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.healthy = ok
}

func (f *fakeProvider) setFailure(failure Failure) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.failure = failure
}

func (f *fakeProvider) setURLErr(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.urlErr = err
}

func (f *fakeProvider) Name() string { return f.name }

func (f *fakeProvider) Binary() BinarySpec {
	return BinarySpec{Name: f.name, Version: "test", EntryName: f.name}
}

func (f *fakeProvider) Args(localPort, controlPort int) []string { return []string{"run"} }

func (f *fakeProvider) PublicURL(_ context.Context, _ int) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.urlCalls++
	if f.urlErr != nil {
		return "", f.urlErr
	}
	return f.url, nil
}

func (f *fakeProvider) Ready(context.Context, int) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.ready, nil
}

func (f *fakeProvider) Healthy(context.Context, int) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.healthy, nil
}

func (f *fakeProvider) ClientIPHeader() string { return f.header }

func (f *fakeProvider) ClassifyFailure([]string) Failure {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.failure
}

type fakeStore struct{ path string }

func (s fakeStore) Ensure(context.Context, BinarySpec) (string, error) { return s.path, nil }

const sleepForeverScript = "#!/bin/sh\nwhile true; do sleep 1; done\n"

const exitImmediatelyScript = "#!/bin/sh\necho 'boom' >&2\nexit 1\n"
