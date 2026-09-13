package tunnel

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
)

type ngrokProvider struct{ configPaths []string }

func NgrokProvider(configPaths []string) Provider {
	return ngrokProvider{configPaths: configPaths}
}

func (ngrokProvider) Name() string { return "ngrok" }

func (ngrokProvider) Binary() BinarySpec {
	return BinarySpec{
		Name:      "ngrok",
		Version:   "stable",
		Archive:   ArchiveZip,
		EntryName: "ngrok",
		URL: func(goos, goarch string) (string, error) {
			target, err := ngrokTarget(goos, goarch)
			if err != nil {
				return "", err
			}
			return "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-" + target + ".zip", nil
		},
		MinVersion: "3.0.0",
	}
}

func ngrokTarget(goos, goarch string) (string, error) {
	arch, ok := map[string]string{"amd64": "amd64", "arm64": "arm64"}[goarch]
	if !ok {
		return "", fmt.Errorf("tunnel: ngrok has no build for %s/%s", goos, goarch)
	}
	switch goos {
	case "darwin", "linux", "windows":
		return goos + "-" + arch, nil
	default:
		return "", fmt.Errorf("tunnel: ngrok has no build for %s/%s", goos, goarch)
	}
}

func (p ngrokProvider) Args(localPort, controlPort int) []string {
	args := []string{"http", fmt.Sprint(localPort)}
	for _, path := range p.configPaths {
		args = append(args, "--config", path)
	}
	return append(args, "--log=stdout", "--log-format=json", "--inspect=false")
}

func (ngrokProvider) PublicURL(ctx context.Context, controlPort int) (string, error) {
	var body struct {
		Tunnels []struct {
			PublicURL string `json:"public_url"`
		} `json:"tunnels"`
	}
	if err := getJSON(ctx, controlURL(controlPort, "/api/tunnels"), &body); err != nil {
		return "", err
	}
	for _, tun := range body.Tunnels {
		if strings.HasPrefix(tun.PublicURL, "https://") {
			return tun.PublicURL, nil
		}
	}
	return "", ErrNoURLYet
}

func (p ngrokProvider) Ready(ctx context.Context, controlPort int) (bool, error) {
	_, err := p.PublicURL(ctx, controlPort)
	if err == nil {
		return true, nil
	}
	return false, nil
}

func (ngrokProvider) Healthy(ctx context.Context, controlPort int) (bool, error) {
	var body struct {
		Status string `json:"status"`
	}
	if err := getJSON(ctx, controlURL(controlPort, "/api/status"), &body); err != nil {
		return false, err
	}
	return body.Status == "online", nil
}

func (ngrokProvider) ClientIPHeader() string { return "" }

func (ngrokProvider) ClassifyFailure(logLines []string) Failure {
	var first string
	for _, line := range logLines {
		var rec struct {
			Err string `json:"err"`
		}
		if json.Unmarshal([]byte(line), &rec) != nil {
			continue
		}
		if rec.Err == "" || rec.Err == "<nil>" {
			continue
		}
		if strings.Contains(rec.Err, "ERR_NGROK_4018") {
			return Failure{Class: FailureCredential, Message: tidyProviderError(rec.Err)}
		}
		if first == "" {
			first = tidyProviderError(rec.Err)
		}
	}
	if first != "" {
		return Failure{Class: FailureRefused, Message: first}
	}
	return Failure{Class: FailureUnknown}
}

func tidyProviderError(raw string) string {
	cleaned := strings.ReplaceAll(raw, "\r", " ")
	cleaned = strings.ReplaceAll(cleaned, "\n", " ")
	return strings.Join(strings.Fields(cleaned), " ")
}
