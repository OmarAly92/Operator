package tunnel

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"testing"
	"time"
)

type fakeProvider struct {
	name          string
	header        string
	binary        string
	mu            sync.Mutex
	url           string
	urlErr        error
	urlDelay      time.Duration
	ready         bool
	healthy       bool
	failure       Failure
	urlCalls      int
	portCalls     map[int]int
	failURLOnPort int
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
		name:      name,
		header:    "X-Forwarded-For",
		binary:    path,
		url:       "https://fake-" + name + ".example",
		ready:     true,
		healthy:   true,
		portCalls: map[int]int{},
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

func (f *fakeProvider) setURLDelay(d time.Duration) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.urlDelay = d
}

func (f *fakeProvider) setFailURLOnPort(port int) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.failURLOnPort = port
}

func (f *fakeProvider) callCount() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.urlCalls
}

func (f *fakeProvider) portCallCount(port int) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.portCalls[port]
}

func (f *fakeProvider) Name() string { return f.name }

func (f *fakeProvider) Binary() BinarySpec {
	return BinarySpec{Name: f.name, Version: "test", EntryName: f.name}
}

func (f *fakeProvider) Args(localPort, controlPort int) []string { return []string{"run"} }

func (f *fakeProvider) PublicURL(_ context.Context, controlPort int) (string, error) {
	f.mu.Lock()
	f.urlCalls++
	f.portCalls[controlPort]++
	delay := f.urlDelay
	urlErr := f.urlErr
	url := f.url
	failPort := f.failURLOnPort
	f.mu.Unlock()

	if delay > 0 {
		time.Sleep(delay)
	}
	if failPort != 0 && controlPort == failPort {
		return "", ErrNoURLYet
	}
	if urlErr != nil {
		return "", urlErr
	}
	return url, nil
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

func (s fakeStore) Resolve(BinarySpec) (string, string, bool) {
	if s.path == "" {
		return "", "", false
	}
	return s.path, "path", true
}

const sleepForeverScript = "#!/bin/sh\nwhile true; do sleep 1; done\n"

const exitImmediatelyScript = "#!/bin/sh\necho 'boom' >&2\nexit 1\n"
