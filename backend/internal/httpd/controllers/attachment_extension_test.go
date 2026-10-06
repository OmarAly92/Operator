package controllers

import "testing"

func TestExtensionForMimeTypeKeepsTextAndCodeExtensions(t *testing.T) {
	cases := map[string]string{
		"text/markdown":    ".md",
		"text/plain":       ".txt",
		"application/json": ".json",
		"application/yaml": ".yaml",
		"application/toml": ".toml",
		"text/x-dart":      ".dart",
		"text/x-go":        ".go",
		"text/typescript":  ".ts",
		"text/tsx":         ".tsx",
		"text/javascript":  ".js",
		"text/x-python":    ".py",
		"text/x-ruby":      ".rb",
		"text/x-rust":      ".rs",
		"text/x-swift":     ".swift",
		"text/x-kotlin":    ".kt",
		"text/x-java":      ".java",
		"application/x-sh": ".sh",
		"application/sql":  ".sql",
		"text/csv":         ".csv",
		"application/xml":  ".xml",
		"text/html":        ".html",
		"text/css":         ".css",
		"image/jpeg":       ".jpg",
		"image/heic":       ".heic",
	}
	for mimeType, want := range cases {
		if got := extensionForMimeType(mimeType); got != want {
			t.Errorf("extensionForMimeType(%q) = %q, want %q", mimeType, got, want)
		}
	}
}
