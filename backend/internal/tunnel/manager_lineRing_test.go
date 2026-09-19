package tunnel

import (
	"fmt"
	"strings"
	"testing"
)

func TestLineRingSurvivesNgrokAccessLogFlood(t *testing.T) {
	ring := newLineRing(logRetention)

	errorLines := []string{
		`{"err":"failed to send authentication request: failed to fetch CRL. errors encountered: asn1: structure error: length too large","lvl":"eror","msg":"failed to reconnect session","obj":"tunnels.session","t":"2026-09-19T10:00:00-07:00"}`,
		`{"err":"failed to send authentication request: failed to fetch CRL. errors encountered: asn1: structure error: length too large","lvl":"eror","msg":"failed to reconnect session","obj":"tunnels.session","t":"2026-09-19T10:00:05-07:00"}`,
		`{"err":"failed to send authentication request: failed to fetch CRL. errors encountered: asn1: structure error: length too large","lvl":"eror","msg":"failed to reconnect session","obj":"tunnels.session","t":"2026-09-19T10:00:10-07:00"}`,
	}

	for _, line := range errorLines {
		ring.Write([]byte(line + "\n"))
	}

	for i := 0; i < 250; i++ {
		startLine := fmt.Sprintf(`{"id":"req-%d","lvl":"info","msg":"start","pg":"/api/tunnels"}`, i)
		endLine := fmt.Sprintf(`{"id":"req-%d","lvl":"info","msg":"end","pg":"/api/tunnels"}`, i)
		ring.Write([]byte(startLine + "\n"))
		ring.Write([]byte(endLine + "\n"))
	}

	lines := ring.Lines()
	found := false
	for _, line := range lines {
		if strings.Contains(line, `"lvl":"eror"`) {
			found = true
			break
		}
	}
	if !found {
		t.Errorf("want at least one CRL-failure line to survive the ring after the noise flood, got %d lines and none matched", len(lines))
	}
}

func TestIsNgrokAccessLogNoise(t *testing.T) {
	tests := []struct {
		name string
		line string
		want bool
	}{
		{
			name: "start line",
			line: `{"id":"abc123","lvl":"info","msg":"start","pg":"/api/tunnels","t":"2026-09-19T10:00:00-07:00"}`,
			want: true,
		},
		{
			name: "end line",
			line: `{"id":"abc123","lvl":"info","msg":"end","pg":"/api/tunnels","t":"2026-09-19T10:00:00-07:00"}`,
			want: true,
		},
		{
			name: "real error line",
			line: `{"err":"failed to send authentication request: failed to fetch CRL. errors encountered: asn1: structure error: length too large","lvl":"eror","msg":"failed to reconnect session","obj":"tunnels.session","t":"2026-09-19T10:00:00-07:00"}`,
			want: false,
		},
		{
			name: "plain string line",
			line: "not json at all",
			want: false,
		},
		{
			name: "empty string",
			line: "",
			want: false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := isNgrokAccessLogNoise(tc.line); got != tc.want {
				t.Errorf("isNgrokAccessLogNoise(%q) = %v, want %v", tc.line, got, tc.want)
			}
		})
	}
}
