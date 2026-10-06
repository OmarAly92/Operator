package domain

import "testing"

func TestParseBackgroundTaskStatus(t *testing.T) {
	for _, name := range []string{"running", "completed", "failed", "killed", "stopped"} {
		got, ok := ParseBackgroundTaskStatus(name)
		if !ok || string(got) != name {
			t.Fatalf("ParseBackgroundTaskStatus(%q) = %q,%v", name, got, ok)
		}
	}
	if _, ok := ParseBackgroundTaskStatus("paused"); ok {
		t.Fatal("unknown status accepted")
	}
	if BackgroundTaskRunning.Finished() || !BackgroundTaskKilled.Finished() {
		t.Fatal("Finished misclassified")
	}
}
