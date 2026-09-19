package tunnel

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os/exec"
	"regexp"
	"strings"
	"time"
)

type NgrokCheck struct {
	Name   string
	OK     bool
	Detail string
}

type NgrokDiagnosis struct {
	Checks  []NgrokCheck
	Summary string
}

var (
	ngrokCRLURL      = "http://crl.ngrok-agent.com/ngrok.crl"
	ngrokConnectAddr = "connect.ngrok-agent.com:443"
)

const ngrokDiagnoseTimeout = 30 * time.Second

func probeCRL(ctx context.Context, target string) NgrokCheck {
	check := NgrokCheck{Name: "CRL over HTTP"}
	client := &http.Client{
		Timeout:       8 * time.Second,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, http.NoBody)
	if err != nil {
		check.Detail = err.Error()
		return check
	}
	res, err := client.Do(req)
	if err != nil {
		check.Detail = "could not reach " + target + ": " + err.Error()
		return check
	}
	defer func() { _ = res.Body.Close() }()
	if res.StatusCode >= 300 && res.StatusCode < 400 || strings.Contains(strings.ToLower(res.Header.Get("Via")), "middlebox") {
		host := "an unknown host"
		if loc, err := url.Parse(res.Header.Get("Location")); err == nil && loc.Host != "" {
			host = loc.Host
		}
		check.Detail = fmt.Sprintf("Plain HTTP is being intercepted on this network (redirected to %s). ngrok cannot authenticate until this is lifted; cloudflared is unaffected.", host)
		return check
	}
	body, err := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if err != nil {
		check.Detail = err.Error()
		return check
	}
	if _, err := x509.ParseRevocationList(body); err != nil {
		check.Detail = fmt.Sprintf("%s returned %d bytes that are not a DER certificate revocation list (%v)", target, len(body), err)
		return check
	}
	check.OK = true
	check.Detail = fmt.Sprintf("fetched %d bytes from %s", len(body), target)
	return check
}

func probeControlPlane(ctx context.Context, addr string) NgrokCheck {
	check := NgrokCheck{Name: "Control plane TLS"}
	dialer := &tls.Dialer{NetDialer: &net.Dialer{Timeout: 8 * time.Second}}
	conn, err := dialer.DialContext(ctx, "tcp", addr)
	if err != nil {
		check.Detail = "TLS to " + addr + " failed: " + err.Error()
		return check
	}
	_ = conn.Close()
	check.OK = true
	check.Detail = "TLS handshake with " + addr + " succeeded"
	return check
}

var diagnoseRow = regexp.MustCompile(`^\s{2}(\S.*?)\s+\[\s*(OK|ERROR|WARN)\s*\]\s*$`)

func parseNgrokDiagnose(output string) []NgrokCheck {
	var checks []NgrokCheck
	group := ""
	firstErr := ""
	inErrors := false
	var errBuf []string
	flushErr := func() {
		if firstErr == "" && len(errBuf) > 0 {
			firstErr = strings.Join(strings.Fields(strings.Join(errBuf, " ")), " ")
		}
		errBuf = nil
	}
	for _, raw := range strings.Split(output, "\n") {
		line := strings.TrimRight(raw, "\r")
		if strings.HasPrefix(line, "Errors and warnings") {
			inErrors = true
			continue
		}
		if inErrors {
			trimmed := strings.TrimSpace(line)
			switch {
			case strings.HasPrefix(trimmed, "- Err:"):
				flushErr()
				errBuf = append(errBuf, strings.TrimPrefix(trimmed, "- Err:"))
			case len(errBuf) > 0 && !strings.HasPrefix(trimmed, "-") && !strings.HasPrefix(trimmed, "*") && trimmed != "":
				errBuf = append(errBuf, trimmed)
			default:
				flushErr()
			}
			continue
		}
		if m := diagnoseRow.FindStringSubmatch(line); m != nil {
			name := strings.TrimSpace(m[1])
			if group != "" {
				name = group + ": " + name
			}
			checks = append(checks, NgrokCheck{Name: name, OK: m[2] == "OK"})
			continue
		}
		if line != "" && !strings.HasPrefix(line, " ") && !strings.HasPrefix(line, "Testing") {
			group = line
			if i := strings.Index(group, " - "); i > 0 {
				group = group[:i]
			}
		}
	}
	flushErr()
	if firstErr != "" {
		for i := range checks {
			if !checks[i].OK {
				checks[i].Detail = firstErr
				break
			}
		}
	}
	return checks
}

func (m *Manager) NgrokDiagnose(ctx context.Context) NgrokDiagnosis {
	ctx, cancel := context.WithTimeout(ctx, ngrokDiagnoseTimeout)
	defer cancel()
	var checks []NgrokCheck

	binary := NgrokCheck{Name: "Binary"}
	var path string
	if provider := m.ngrokProvider(); provider != nil {
		if resolver, ok := m.binaries.(binaryResolver); ok {
			if p, source, ok := resolver.Resolve(provider.Binary()); ok {
				path = p
				out, err := exec.CommandContext(ctx, p, "version").Output()
				if err == nil {
					binary.OK = true
					binary.Detail = fmt.Sprintf("%s (%s): %s", p, source, strings.TrimSpace(strings.SplitN(string(out), "\n", 2)[0]))
				} else {
					binary.Detail = fmt.Sprintf("%s failed to run: %v", p, err)
				}
			} else {
				binary.Detail = "ngrok is not installed and has not been downloaded yet; enabling the tunnel downloads it"
			}
		}
	}
	checks = append(checks, binary, probeCRL(ctx, ngrokCRLURL), probeControlPlane(ctx, ngrokConnectAddr))

	if path != "" {
		args := []string{"diagnose"}
		if p, ok := m.ngrokProvider().(ngrokProvider); ok {
			for _, cfg := range p.configPaths() {
				args = append(args, "--config", cfg)
			}
		}
		out, _ := exec.CommandContext(ctx, path, args...).CombinedOutput()
		parsed := parseNgrokDiagnose(string(out))
		if len(parsed) == 0 {
			checks = append(checks, NgrokCheck{Name: "ngrok diagnose", Detail: strings.TrimSpace(string(out))})
		}
		checks = append(checks, parsed...)
	}

	cred, _ := m.ngrokCredential()
	credential := NgrokCheck{Name: "Credential", OK: cred.Present}
	switch cred.Source {
	case "operator":
		credential.Detail = "authtoken stored by Operator"
	case "system":
		credential.Detail = "using the system ngrok login at " + cred.SystemConfigPath
	default:
		credential.Detail = "no authtoken; ngrok will fall back to cloudflared"
	}
	checks = append(checks, credential)

	summary := "ngrok can connect from this machine."
	for _, c := range checks {
		if !c.OK {
			summary = c.Detail
			break
		}
	}
	return NgrokDiagnosis{Checks: checks, Summary: summary}
}
