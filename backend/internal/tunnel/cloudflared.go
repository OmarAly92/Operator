package tunnel

import (
	"context"
	"fmt"
	"net/http"
	"strings"
)

type cloudflaredProvider struct{}

func CloudflaredProvider() Provider { return cloudflaredProvider{} }

func (cloudflaredProvider) Name() string { return "cloudflared" }

const cloudflaredVersion = "2026.3.0"

func (cloudflaredProvider) Binary() BinarySpec {
	return BinarySpec{
		Name:      "cloudflared",
		Version:   cloudflaredVersion,
		Archive:   ArchiveTarGz,
		EntryName: "cloudflared",
		URL: func(goos, goarch string) (string, error) {
			if goarch != "amd64" && goarch != "arm64" {
				return "", fmt.Errorf("tunnel: cloudflared has no build for %s/%s", goos, goarch)
			}
			return "https://github.com/cloudflare/cloudflared/releases/download/" +
				cloudflaredVersion + "/cloudflared-" + goos + "-" + goarch + ".tgz", nil
		},
		SHA256: cloudflaredChecksums,
	}
}

func (cloudflaredProvider) Args(localPort, controlPort int) []string {
	return []string{
		"tunnel", "--no-autoupdate",
		"--metrics", fmt.Sprintf("127.0.0.1:%d", controlPort),
		"--url", fmt.Sprintf("http://127.0.0.1:%d", localPort),
	}
}

func (cloudflaredProvider) PublicURL(ctx context.Context, controlPort int) (string, error) {
	var body struct {
		Hostname string `json:"hostname"`
	}
	if err := getJSON(ctx, controlURL(controlPort, "/quicktunnel"), &body); err != nil {
		return "", err
	}
	if body.Hostname == "" {
		return "", ErrNoURLYet
	}
	return "https://" + body.Hostname, nil
}

func (cloudflaredProvider) Ready(ctx context.Context, controlPort int) (bool, error) {
	var body struct {
		ReadyConnections int `json:"readyConnections"`
	}
	code, err := getJSONStatus(ctx, controlURL(controlPort, "/ready"), &body)
	if err != nil {
		return false, err
	}
	if code == http.StatusServiceUnavailable {
		return false, nil
	}
	if code != http.StatusOK {
		return false, fmt.Errorf("tunnel: cloudflared /ready returned %d", code)
	}
	return body.ReadyConnections >= 1, nil
}

func (p cloudflaredProvider) Healthy(ctx context.Context, controlPort int) (bool, error) {
	return p.Ready(ctx, controlPort)
}

func (cloudflaredProvider) ClientIPHeader() string { return "Cf-Connecting-Ip" }

func (cloudflaredProvider) ClassifyFailure(logLines []string) Failure {
	for _, line := range logLines {
		if strings.Contains(line, "ERR ") || strings.Contains(line, "error=") {
			return Failure{Class: FailureRefused, Message: tidyProviderError(line)}
		}
	}
	return Failure{Class: FailureUnknown}
}
