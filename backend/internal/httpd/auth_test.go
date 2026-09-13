package httpd

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/mobilebridge"
	"github.com/OmarAly92/operator/backend/internal/tunnel"
)

func newAuthUnderTest(pw string, now func() time.Time) (http.Handler, *lockout) {
	st := &authState{}
	h := mobilebridge.HashPassword(pw)
	st.setHash(h)
	lock := newLockout(5, time.Minute, now)
	ok := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) })
	return authMiddleware(st, lock, nil, &forwardedTrust{})(ok), lock
}

func req(auth string) *http.Request {
	r := httptest.NewRequest(http.MethodGet, "/api/v1/sessions", nil)
	r.RemoteAddr = "192.168.1.50:5555"
	if auth != "" {
		r.Header.Set("Authorization", auth)
	}
	return r
}

func reqFrom(remoteAddr, auth string) *http.Request {
	r := httptest.NewRequest(http.MethodGet, "/api/v1/sessions", nil)
	r.RemoteAddr = remoteAddr
	if auth != "" {
		r.Header.Set("Authorization", auth)
	}
	return r
}

func TestAuthLockoutResetsAfterCooldown(t *testing.T) {
	nowP := time.Now()
	h, _ := newAuthUnderTest("secret12", func() time.Time { return nowP })
	// Lock the source with 5 failures.
	for i := 0; i < 5; i++ {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, req("Bearer wrong"))
	}
	// Still within cooldown → 429 even with the right password.
	w := httptest.NewRecorder()
	h.ServeHTTP(w, req("Bearer secret12"))
	if w.Code != http.StatusTooManyRequests {
		t.Fatalf("during cooldown: got %d want 429", w.Code)
	}
	// Advance past the 1-minute cooldown.
	nowP = nowP.Add(time.Minute + time.Second)
	// A single WRONG attempt must NOT immediately re-lock — it starts a fresh
	// window and returns 401, not 429.
	w = httptest.NewRecorder()
	h.ServeHTTP(w, req("Bearer wrong"))
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("first attempt after cooldown: got %d want 401 (fresh window, not re-locked)", w.Code)
	}
	// And the correct password now succeeds.
	w = httptest.NewRecorder()
	h.ServeHTTP(w, req("Bearer secret12"))
	if w.Code != http.StatusOK {
		t.Fatalf("correct password after cooldown: got %d want 200", w.Code)
	}
}

func TestAuthRejectsMissingAndWrong(t *testing.T) {
	h, _ := newAuthUnderTest("secret12", time.Now)
	for _, tc := range []struct {
		name, auth string
		want       int
	}{
		{"missing", "", http.StatusUnauthorized},
		{"wrong", "Bearer nope", http.StatusUnauthorized},
		{"right", "Bearer secret12", http.StatusOK},
	} {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, req(tc.auth))
		if w.Code != tc.want {
			t.Errorf("%s: got %d want %d", tc.name, w.Code, tc.want)
		}
	}
}

func TestAuthLockoutAfterFive(t *testing.T) {
	now := time.Now()
	h, _ := newAuthUnderTest("secret12", func() time.Time { return now })
	for i := 0; i < 5; i++ {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, req("Bearer wrong"))
		if w.Code != http.StatusUnauthorized {
			t.Fatalf("attempt %d: got %d want 401", i, w.Code)
		}
	}
	// 6th attempt — even with the RIGHT password — is locked out.
	w := httptest.NewRecorder()
	h.ServeHTTP(w, req("Bearer secret12"))
	if w.Code != http.StatusTooManyRequests {
		t.Fatalf("locked attempt: got %d want 429", w.Code)
	}
}

// reqPathCookie builds a request to an arbitrary path, optionally carrying the
// Bearer header and/or the preview auth cookie, for the preview-cookie tests.
func reqPathCookie(method, path, auth, cookie string) *http.Request {
	r := httptest.NewRequest(method, path, nil)
	r.RemoteAddr = "192.168.1.50:5555"
	if auth != "" {
		r.Header.Set("Authorization", auth)
	}
	if cookie != "" {
		r.AddCookie(&http.Cookie{Name: authCookieName, Value: cookie})
	}
	return r
}

// A preview subresource (image/CSS/JS) is fetched by the WebView WITHOUT our
// Authorization header, carrying only the cookie the top-level load set. It must
// authenticate on the preview-files path.
func TestPreviewCookieAuthenticatesSubresource(t *testing.T) {
	h, _ := newAuthUnderTest("secret12", time.Now)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, reqPathCookie(http.MethodGet, "/api/v1/sessions/abc/preview/files/logo.png", "", "secret12"))
	if w.Code != http.StatusOK {
		t.Fatalf("preview subresource with cookie: got %d want 200", w.Code)
	}
}

// The top-level preview file load (Bearer header) must set the auth cookie,
// scoped tightly to that session's preview-files directory and HttpOnly.
func TestPreviewFileSetsScopedCookie(t *testing.T) {
	h, _ := newAuthUnderTest("secret12", time.Now)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, reqPathCookie(http.MethodGet, "/api/v1/sessions/abc/preview/files/index.html", "Bearer secret12", ""))
	if w.Code != http.StatusOK {
		t.Fatalf("preview index with bearer: got %d want 200", w.Code)
	}
	var c *http.Cookie
	for _, ck := range w.Result().Cookies() {
		if ck.Name == authCookieName {
			c = ck
		}
	}
	if c == nil {
		t.Fatal("expected auth cookie on preview file response")
		return
	}
	if c.Path != "/api/v1/sessions/abc/preview/files/" { //nolint:staticcheck // SA5011 false positive: t.Fatal above halts the test
		t.Errorf("cookie Path = %q, want /api/v1/sessions/abc/preview/files/", c.Path)
	}
	if !c.HttpOnly {
		t.Error("cookie must be HttpOnly")
	}
}

// After a password regenerate the WebView still holds the cookie minted under the
// OLD password. The top-level load re-authenticates via the Bearer header (the
// mobile app has the new password), so the server must overwrite the stale cookie
// — otherwise the page's subresources keep sending the old token and 401.
func TestPreviewCookieRefreshedAfterPasswordChange(t *testing.T) {
	h, _ := newAuthUnderTest("newpass12", time.Now)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, reqPathCookie(http.MethodGet,
		"/api/v1/sessions/abc/preview/files/index.html", "Bearer newpass12", "oldpass12"))
	if w.Code != http.StatusOK {
		t.Fatalf("preview index with new bearer + stale cookie: got %d want 200", w.Code)
	}
	var c *http.Cookie
	for _, ck := range w.Result().Cookies() {
		if ck.Name == authCookieName {
			c = ck
		}
	}
	if c == nil {
		t.Fatal("expected stale auth cookie to be refreshed")
		return
	}
	if c.Value != "newpass12" { //nolint:staticcheck // SA5011 false positive: t.Fatal above halts the test
		t.Errorf("cookie Value = %q, want the current token newpass12", c.Value)
	}
}

// The cookie must NOT authenticate any non-preview endpoint: a preview page that
// tries POST /kill with only the cookie is rejected. This is the server-side
// half of the guarantee (the cookie's Path already stops the browser sending it
// here at all).
func TestPreviewCookieRejectedOnOtherEndpoints(t *testing.T) {
	h, _ := newAuthUnderTest("secret12", time.Now)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, reqPathCookie(http.MethodPost, "/api/v1/sessions/abc/kill", "", "secret12"))
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("cookie on /kill: got %d want 401", w.Code)
	}
}

// A normal (non-preview) authenticated request must not get an auth cookie set,
// so the cookie only ever exists for the preview flow.
func TestNoCookieSetOnNonPreviewRoutes(t *testing.T) {
	h, _ := newAuthUnderTest("secret12", time.Now)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, req("Bearer secret12")) // path /api/v1/sessions
	if w.Code != http.StatusOK {
		t.Fatalf("got %d want 200", w.Code)
	}
	for _, ck := range w.Result().Cookies() {
		if ck.Name == authCookieName {
			t.Fatal("auth cookie must not be set on a non-preview route")
		}
	}
}

func TestAuthLockoutIsPerSource(t *testing.T) {
	now := time.Now()
	h, _ := newAuthUnderTest("secret12", func() time.Time { return now })

	// Source A: lock with 5 failed attempts from 192.168.1.50
	sourceA := "192.168.1.50:5555"
	for i := 0; i < 5; i++ {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, reqFrom(sourceA, "Bearer wrong"))
		if w.Code != http.StatusUnauthorized {
			t.Fatalf("source A attempt %d: got %d want 401", i, w.Code)
		}
	}
	// Verify source A is now locked
	w := httptest.NewRecorder()
	h.ServeHTTP(w, reqFrom(sourceA, "Bearer secret12"))
	if w.Code != http.StatusTooManyRequests {
		t.Fatalf("source A locked check: got %d want 429", w.Code)
	}

	// Source B: should NOT be locked despite source A being locked
	sourceB := "192.168.1.99:6666"
	// B with correct password should be 200, not 429
	w = httptest.NewRecorder()
	h.ServeHTTP(w, reqFrom(sourceB, "Bearer secret12"))
	if w.Code != http.StatusOK {
		t.Fatalf("source B with correct password: got %d want 200", w.Code)
	}

	// B with wrong password should be 401, not 429
	w = httptest.NewRecorder()
	h.ServeHTTP(w, reqFrom(sourceB, "Bearer wrong"))
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("source B with wrong password: got %d want 401", w.Code)
	}
}

func TestSourceKeyUsesRemoteAddrByDefault(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/api/v1/sessions", nil)
	req.RemoteAddr = "192.168.1.44:52133"
	if got := sourceKey(req, &forwardedTrust{}); got != "192.168.1.44" {
		t.Errorf("got %q, want 192.168.1.44", got)
	}
}

func TestSourceKeyHonorsForwardedHeaderFromLoopback(t *testing.T) {
	trust := &forwardedTrust{}
	trust.Set("Cf-Connecting-Ip")

	req := httptest.NewRequest(http.MethodGet, "/api/v1/sessions", nil)
	req.RemoteAddr = "127.0.0.1:41111"
	req.Header.Set("Cf-Connecting-Ip", "203.0.113.9")

	if got := sourceKey(req, trust); got != "203.0.113.9" {
		t.Errorf("got %q, want the forwarded client ip", got)
	}
}

func TestSourceKeyIgnoresForwardedHeaderFromNonLoopback(t *testing.T) {
	trust := &forwardedTrust{}
	trust.Set("X-Forwarded-For")

	req := httptest.NewRequest(http.MethodGet, "/api/v1/sessions", nil)
	req.RemoteAddr = "192.168.1.44:52133"
	req.Header.Set("X-Forwarded-For", "203.0.113.9")

	if got := sourceKey(req, trust); got != "192.168.1.44" {
		t.Errorf("got %q — a LAN client must not be able to forge its lockout bucket", got)
	}
}

func TestSourceKeyIgnoresForwardedHeaderWhenNoTunnelIsLive(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/api/v1/sessions", nil)
	req.RemoteAddr = "127.0.0.1:41111"
	req.Header.Set("X-Forwarded-For", "203.0.113.9")

	if got := sourceKey(req, &forwardedTrust{}); got != "127.0.0.1" {
		t.Errorf("got %q, want 127.0.0.1 when no tunnel is running", got)
	}
}

func TestSourceKeyTakesFirstEntryOfMultiValuedForwardedFor(t *testing.T) {
	trust := &forwardedTrust{}
	trust.Set("X-Forwarded-For")

	req := httptest.NewRequest(http.MethodGet, "/api/v1/sessions", nil)
	req.RemoteAddr = "127.0.0.1:41111"
	req.Header.Set("X-Forwarded-For", "203.0.113.9, 70.41.3.18, 150.172.238.178")

	if got := sourceKey(req, trust); got != "203.0.113.9" {
		t.Errorf("got %q, want the left-most (client) entry", got)
	}
}

func TestSourceKeyFallsBackWhenForwardedHeaderIsEmptyOrJunk(t *testing.T) {
	trust := &forwardedTrust{}
	trust.Set("X-Forwarded-For")

	for name, value := range map[string]string{"empty": "", "commas": " , ,"} {
		req := httptest.NewRequest(http.MethodGet, "/api/v1/sessions", nil)
		req.RemoteAddr = "127.0.0.1:41111"
		req.Header.Set("X-Forwarded-For", value)
		if got := sourceKey(req, trust); got != "127.0.0.1" {
			t.Errorf("%s: got %q, want the remote addr fallback", name, got)
		}
	}
}

func TestSourceKeySeparatesTwoTunneledClientsIntoDifferentBuckets(t *testing.T) {
	trust := &forwardedTrust{}
	trust.Set("Cf-Connecting-Ip")

	first := httptest.NewRequest(http.MethodGet, "/api/v1/sessions", nil)
	first.RemoteAddr = "127.0.0.1:41111"
	first.Header.Set("Cf-Connecting-Ip", "203.0.113.9")

	second := httptest.NewRequest(http.MethodGet, "/api/v1/sessions", nil)
	second.RemoteAddr = "127.0.0.1:41112"
	second.Header.Set("Cf-Connecting-Ip", "198.51.100.7")

	if sourceKey(first, trust) == sourceKey(second, trust) {
		t.Error("two tunneled clients must not share one lockout bucket")
	}
}

func TestSourceKeyFallsBackToRemoteAddrWhenLiveProviderIsNgrok(t *testing.T) {
	trust := &forwardedTrust{}
	trust.Set(tunnel.NgrokProvider(tunnel.NgrokConfig{}).ClientIPHeader())

	req := httptest.NewRequest(http.MethodGet, "/api/v1/sessions", nil)
	req.RemoteAddr = "127.0.0.1:41111"
	req.Header.Set("X-Forwarded-For", "6.6.6.6")

	if got := sourceKey(req, trust); got != "127.0.0.1" {
		t.Errorf("got %q, want RemoteAddr fallback because ngrok's forwarded header is not trustworthy", got)
	}
}

func TestSourceKeyTrustsRemoteAddrHeaderWhenLiveProviderIsCloudflared(t *testing.T) {
	trust := &forwardedTrust{}
	trust.Set(tunnel.CloudflaredProvider().ClientIPHeader())

	req := httptest.NewRequest(http.MethodGet, "/api/v1/sessions", nil)
	req.RemoteAddr = "127.0.0.1:41111"
	req.Header.Set("Cf-Connecting-Ip", "203.0.113.9")

	if got := sourceKey(req, trust); got != "203.0.113.9" {
		t.Errorf("got %q, want the forwarded client ip because cloudflared's header is trustworthy", got)
	}
}

func TestLANManagerSetTrustedForwardHeaderReachesAuth(t *testing.T) {
	manager := NewMobileLAN(http.NotFoundHandler(), 0, nil, nil)
	manager.SetTrustedForwardHeader("Cf-Connecting-Ip")

	req := httptest.NewRequest(http.MethodGet, "/api/v1/sessions", nil)
	req.RemoteAddr = "127.0.0.1:41111"
	req.Header.Set("Cf-Connecting-Ip", "203.0.113.9")

	if got := sourceKey(req, manager.forwarded); got != "203.0.113.9" {
		t.Errorf("got %q, want the header set through the manager", got)
	}

	manager.SetTrustedForwardHeader("")
	if got := sourceKey(req, manager.forwarded); got != "127.0.0.1" {
		t.Errorf("got %q, want trust cleared when the tunnel stops", got)
	}
}

func newStrongAuthUnderTest(pw string, now func() time.Time) http.Handler {
	st := &authState{}
	st.setHash(mobilebridge.HashPassword(pw))
	st.setStrong(true)
	lock := newLockout(5, time.Minute, now)
	ok := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) })
	return authMiddleware(st, lock, nil, &forwardedTrust{})(ok)
}

func TestStrongPasswordIsNeverBlockedByTheSharedTunnelBucket(t *testing.T) {
	const pw = "averylongtunnelpasswor"
	h := newStrongAuthUnderTest(pw, time.Now)

	for i := 0; i < 10; i++ {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, reqFrom("127.0.0.1:41111", "Bearer wrong"))
	}

	w := httptest.NewRecorder()
	h.ServeHTTP(w, reqFrom("127.0.0.1:41112", "Bearer "+pw))
	if w.Code != http.StatusOK {
		t.Fatalf("correct long password from the shared tunnel bucket: got %d want 200", w.Code)
	}
}

func TestStrongPasswordStillThrottlesWrongGuesses(t *testing.T) {
	h := newStrongAuthUnderTest("averylongtunnelpasswor", time.Now)

	var last int
	for i := 0; i < 6; i++ {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, reqFrom("127.0.0.1:41111", "Bearer wrong"))
		last = w.Code
	}
	if last != http.StatusTooManyRequests {
		t.Fatalf("wrong guesses past the limit: got %d want 429", last)
	}
}

func TestShortPasswordKeepsBlockingEvenTheCorrectPassword(t *testing.T) {
	h, _ := newAuthUnderTest("secret12", time.Now)

	for i := 0; i < 5; i++ {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, reqFrom("127.0.0.1:41111", "Bearer wrong"))
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, reqFrom("127.0.0.1:41111", "Bearer secret12"))
	if w.Code != http.StatusTooManyRequests {
		t.Fatalf("short LAN password during lockout: got %d want 429 — the LAN behavior must not change", w.Code)
	}
}

func TestLANManagerSetPasswordStrongReachesAuth(t *testing.T) {
	manager := NewMobileLAN(http.NotFoundHandler(), 0, nil, nil)
	if manager.PasswordStrong() {
		t.Fatal("a new manager must start with the short-password rules")
	}
	manager.SetPasswordStrong(true)
	if !manager.PasswordStrong() || !manager.state.isStrong() {
		t.Fatal("SetPasswordStrong must write through to the shared authState")
	}
}
