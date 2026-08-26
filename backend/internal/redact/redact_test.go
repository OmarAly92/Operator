package redact

import "testing"

func TestTextRedactsKnownSecretShapes(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want string
	}{
		{"aws access key", "key=AKIAIOSFODNN7EXAMPLE done", "key=[redacted] done"},
		{"github token", "ghp_0123456789abcdefghijklmnopqrstuvwxyz", "[redacted]"},
		{"bearer header", "Authorization: Bearer abc.def.ghijklmnop", "Authorization: Bearer [redacted]"},
		{"url password", "https://user:hunter2@example.com/x", "https://user:[redacted]@example.com/x"},
		{"nothing to do", "ls -la /tmp", "ls -la /tmp"},
	}
	for _, tt := range tests {
		got := Text(tt.in)
		if got.Text != tt.want {
			t.Fatalf("%s: Text(%q).Text = %q want %q", tt.name, tt.in, got.Text, tt.want)
		}
	}
}

func TestTextReportsSpansIntoReturnedText(t *testing.T) {
	got := Text("key=AKIAIOSFODNN7EXAMPLE done")
	if len(got.Spans) != 1 {
		t.Fatalf("Spans = %v, want exactly one", got.Spans)
	}
	if got.Text[got.Spans[0].Start:got.Spans[0].End] != mask {
		t.Fatalf("span %v does not cover the mask in %q", got.Spans[0], got.Text)
	}
}

func TestTextLeavesEmptyInputAlone(t *testing.T) {
	got := Text("")
	if got.Text != "" || len(got.Spans) != 0 {
		t.Fatalf("Text(\"\") = %+v, want empty", got)
	}
}
