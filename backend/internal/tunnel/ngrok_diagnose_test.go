package tunnel

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"math/big"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestParseNgrokDiagnoseNamesGroupsAndAttachesTheFirstError(t *testing.T) {
	raw, err := os.ReadFile("testdata/ngrok-diagnose-crl.txt")
	if err != nil {
		t.Fatal(err)
	}
	checks := parseNgrokDiagnose(string(raw))
	if len(checks) != 7 {
		t.Fatalf("got %d checks: %+v", len(checks), checks)
	}
	if checks[0].Name != "Internet Connectivity: Name Resolution" || !checks[0].OK {
		t.Errorf("check 0 = %+v", checks[0])
	}
	last := checks[6]
	if last.Name != "Ngrok Connectivity: TLS" || last.OK {
		t.Errorf("check 6 = %+v", last)
	}
	if !strings.Contains(last.Detail, "No tunnel servers could establish a TLS connection. (ERR_NGROK_8008)") {
		t.Errorf("detail = %q", last.Detail)
	}
}

func derCRL(t *testing.T) []byte {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	tmpl := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "t"}, NotBefore: time.Now(), NotAfter: time.Now().Add(time.Hour), KeyUsage: x509.KeyUsageCRLSign, IsCA: true, BasicConstraintsValid: true}
	certDER, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	cert, _ := x509.ParseCertificate(certDER)
	crl, err := x509.CreateRevocationList(rand.Reader, &x509.RevocationList{Number: big.NewInt(1), ThisUpdate: time.Now(), NextUpdate: time.Now().Add(time.Hour)}, cert, key)
	if err != nil {
		t.Fatal(err)
	}
	return crl
}

func TestProbeCRL(t *testing.T) {
	cases := []struct {
		name    string
		handler http.HandlerFunc
		wantOK  bool
		wantIn  string
	}{
		{"der", func(w http.ResponseWriter, _ *http.Request) { _, _ = w.Write(derCRL(t)) }, true, ""},
		{"middlebox", func(w http.ResponseWriter, _ *http.Request) {
			w.Header().Set("Via", "1.0 middlebox")
			w.Header().Set("Location", "http://megaplusredirection.tedata.net/VDSL-Redirection_100.html")
			w.WriteHeader(http.StatusTemporaryRedirect)
		}, false, "intercepted on this network (redirected to megaplusredirection.tedata.net)"},
		{"pem", func(w http.ResponseWriter, _ *http.Request) {
			_, _ = w.Write([]byte("-----BEGIN X509 CRL-----\nMIIB\n"))
		}, false, "not a DER certificate revocation list"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			srv := httptest.NewServer(tc.handler)
			defer srv.Close()
			got := probeCRL(context.Background(), srv.URL+"/ngrok.crl")
			if got.OK != tc.wantOK || !strings.Contains(got.Detail, tc.wantIn) {
				t.Fatalf("got %+v, want ok=%v detail containing %q", got, tc.wantOK, tc.wantIn)
			}
		})
	}
}

func TestNgrokDiagnoseSummaryIsTheFirstFailure(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Via", "1.0 middlebox")
		w.WriteHeader(http.StatusTemporaryRedirect)
	}))
	defer srv.Close()
	prevURL, prevAddr := ngrokCRLURL, ngrokConnectAddr
	ngrokCRLURL, ngrokConnectAddr = srv.URL+"/ngrok.crl", "127.0.0.1:1"
	defer func() { ngrokCRLURL, ngrokConnectAddr = prevURL, prevAddr }()

	fake := newFakeProvider(t, "ngrok", "#!/bin/sh\ncat \"$(dirname \"$0\")/../diagnose.txt\" 2>/dev/null || cat testdata/ngrok-diagnose-crl.txt\n")
	m := New(Deps{Dir: t.TempDir(), Binaries: fakeStore{path: fake.binary}, Now: time.Now, Providers: []Provider{
		NgrokProvider(NgrokConfig{OwnConfigPath: "/nonexistent/ngrok.yml"}),
	}})
	d := m.NgrokDiagnose(context.Background())
	if len(d.Checks) < 3 {
		t.Fatalf("checks = %+v", d.Checks)
	}
	if d.Checks[0].Name != "Binary" {
		t.Errorf("first check = %+v", d.Checks[0])
	}
	if !strings.Contains(d.Summary, "intercepted") {
		t.Errorf("summary = %q, want the CRL interception to lead", d.Summary)
	}
}

func TestProbeControlPlaneAcceptsAPrivateCA(t *testing.T) {
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) }))
	defer srv.Close()
	addr := strings.TrimPrefix(srv.URL, "https://")
	got := probeControlPlane(context.Background(), addr)
	if !got.OK {
		t.Fatalf("a reachable control plane with an untrusted CA must pass the reachability probe: %+v", got)
	}
	if got := probeControlPlane(context.Background(), "127.0.0.1:1"); got.OK {
		t.Fatal("a closed port must fail")
	}
}

func TestNgrokDiagnoseOnlyPassesConfigFilesThatExist(t *testing.T) {
	dir := t.TempDir()
	argsFile := filepath.Join(dir, "args")
	fake := newFakeProvider(t, "ngrok", "#!/bin/sh\nif [ \"$1\" = diagnose ]; then echo \"$@\" > \""+argsFile+"\"; fi\necho ngrok version 3.39.6\n")
	user := filepath.Join(dir, "user.yml")
	if err := os.WriteFile(user, []byte("version: \"3\"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	prevURL, prevAddr := ngrokCRLURL, ngrokConnectAddr
	ngrokCRLURL, ngrokConnectAddr = "http://127.0.0.1:1/ngrok.crl", "127.0.0.1:1"
	defer func() { ngrokCRLURL, ngrokConnectAddr = prevURL, prevAddr }()
	m := New(Deps{Dir: dir, Binaries: fakeStore{path: fake.binary}, Now: time.Now, Providers: []Provider{
		NgrokProvider(NgrokConfig{UserConfigPath: user, OwnConfigPath: filepath.Join(dir, "missing", "ngrok.yml")}),
	}})
	_ = m.NgrokDiagnose(context.Background())
	args, err := os.ReadFile(argsFile)
	if err != nil {
		t.Fatalf("ngrok diagnose was not invoked: %v", err)
	}
	if !strings.Contains(string(args), user) || strings.Contains(string(args), "missing") {
		t.Fatalf("args = %q, want only the existing user config", args)
	}
}
