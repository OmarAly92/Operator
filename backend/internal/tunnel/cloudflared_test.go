package tunnel

import (
	"context"
	"net/http"
	"net/http/httptest"
	"runtime"
	"testing"
)

func TestCloudflaredPublicURLFromQuickTunnel(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/quicktunnel" {
			t.Errorf("unexpected path %q", r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"hostname":"cradle-compatibility-biology-saskatchewan.trycloudflare.com"}`))
	}))
	defer srv.Close()

	got, err := CloudflaredProvider().PublicURL(context.Background(), controlPortOf(t, srv))
	if err != nil {
		t.Fatalf("PublicURL: %v", err)
	}
	if want := "https://cradle-compatibility-biology-saskatchewan.trycloudflare.com"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestCloudflaredReadyCountsConnections(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"status":200,"readyConnections":1,"connectorId":"c687b758"}`))
	}))
	defer srv.Close()

	ok, err := CloudflaredProvider().Ready(context.Background(), controlPortOf(t, srv))
	if err != nil {
		t.Fatalf("Ready: %v", err)
	}
	if !ok {
		t.Error("want ready with readyConnections 1")
	}
}

func TestCloudflaredReadyTolerates503WhileConnecting(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer srv.Close()

	ok, err := CloudflaredProvider().Ready(context.Background(), controlPortOf(t, srv))
	if err != nil {
		t.Fatalf("503 while connecting must not be an error, got %v", err)
	}
	if ok {
		t.Error("want not ready")
	}
}

func TestCloudflaredReadyFalseWithZeroConnections(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"status":200,"readyConnections":0}`))
	}))
	defer srv.Close()

	ok, _ := CloudflaredProvider().Ready(context.Background(), controlPortOf(t, srv))
	if ok {
		t.Error("want not ready with zero connections")
	}
}

func TestCloudflaredArgsRequestAQuickTunnel(t *testing.T) {
	args := CloudflaredProvider().Args(3011, 50893)
	joined := " " + stringsJoin(args, " ") + " "
	for _, want := range []string{" tunnel ", " --no-autoupdate ", " --url http://127.0.0.1:3011 ", " --metrics 127.0.0.1:50893 "} {
		if !containsString(joined, want) {
			t.Errorf("args %v missing %q", args, want)
		}
	}
}

func TestCloudflaredClientIPHeaderPrefersCfConnectingIP(t *testing.T) {
	if got := CloudflaredProvider().ClientIPHeader(); got != "Cf-Connecting-Ip" {
		t.Errorf("got %q, want Cf-Connecting-Ip", got)
	}
	if got := NgrokProvider(nil).ClientIPHeader(); got != "X-Forwarded-For" {
		t.Errorf("got %q, want X-Forwarded-For", got)
	}
}

func TestCloudflaredBinaryPlatformSpecific(t *testing.T) {
	spec := CloudflaredProvider().Binary()

	tests := []struct {
		goos      string
		goarch    string
		archive   ArchiveKind
		hasSuffix bool
	}{
		{"darwin", "amd64", ArchiveTarGz, true},
		{"darwin", "arm64", ArchiveTarGz, true},
		{"linux", "amd64", ArchiveRaw, false},
		{"linux", "arm64", ArchiveRaw, false},
	}

	for _, tt := range tests {
		url, err := spec.URL(tt.goos, tt.goarch)
		if err != nil {
			t.Errorf("URL(%s, %s): %v", tt.goos, tt.goarch, err)
			continue
		}

		hasTarGz := len(url) >= 4 && url[len(url)-4:] == ".tgz"
		if tt.hasSuffix && !hasTarGz {
			t.Errorf("URL(%s, %s) = %q, want .tgz suffix", tt.goos, tt.goarch, url)
		} else if !tt.hasSuffix && hasTarGz {
			t.Errorf("URL(%s, %s) = %q, should not have .tgz suffix", tt.goos, tt.goarch, url)
		}
	}

	if runtime.GOOS == "darwin" && spec.Archive != ArchiveTarGz {
		t.Errorf("on darwin, expected ArchiveTarGz, got %v", spec.Archive)
	} else if runtime.GOOS == "linux" && spec.Archive != ArchiveRaw {
		t.Errorf("on linux, expected ArchiveRaw, got %v", spec.Archive)
	}
}
