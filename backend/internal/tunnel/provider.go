package tunnel

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"strconv"
	"time"
)

var ErrNoURLYet = errors.New("tunnel: public url not published yet")

type ArchiveKind int

const (
	ArchiveZip ArchiveKind = iota
	ArchiveTarGz
)

type BinarySpec struct {
	Name       string
	Version    string
	Archive    ArchiveKind
	EntryName  string
	URL        func(goos, goarch string) (string, error)
	SHA256     map[string]string
	MinVersion string
}

type Provider interface {
	Name() string
	Binary() BinarySpec
	Args(localPort, controlPort int) []string
	PublicURL(ctx context.Context, controlPort int) (string, error)
	Ready(ctx context.Context, controlPort int) (bool, error)
	Healthy(ctx context.Context, controlPort int) (bool, error)
	ClientIPHeader() string
	ClassifyFailure(logLines []string) Failure
}

var controlClient = &http.Client{Timeout: 3 * time.Second}

func controlURL(controlPort int, path string) string {
	return "http://" + net.JoinHostPort("127.0.0.1", strconv.Itoa(controlPort)) + path
}

func getJSON(ctx context.Context, url string, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	res, err := controlClient.Do(req)
	if err != nil {
		return err
	}
	defer func() { _ = res.Body.Close() }()
	if res.StatusCode != http.StatusOK {
		return fmt.Errorf("tunnel: %s returned %d", url, res.StatusCode)
	}
	return json.NewDecoder(res.Body).Decode(out)
}

func getJSONStatus(ctx context.Context, url string, out any) (int, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return 0, err
	}
	res, err := controlClient.Do(req)
	if err != nil {
		return 0, err
	}
	defer func() { _ = res.Body.Close() }()
	if res.StatusCode != http.StatusOK {
		return res.StatusCode, nil
	}
	return res.StatusCode, json.NewDecoder(res.Body).Decode(out)
}
