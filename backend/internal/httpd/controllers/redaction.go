package controllers

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
	"github.com/OmarAly92/operator/backend/internal/redact"
)

// RedactionController publishes the daemon's built-in secret shapes so a client
// that paints text the daemon never saw -- the desktop terminal renders from
// the PTY stream directly -- can mask exactly what the daemon redacts.
type RedactionController struct{}

type RedactionPattern struct {
	Source string `json:"source"`
	Flags  string `json:"flags"`
}

type RedactionPatternsResponse struct {
	Patterns []RedactionPattern `json:"patterns"`
}

func (c *RedactionController) Register(r chi.Router) {
	r.Get("/redaction/patterns", c.Patterns)
}

func (c *RedactionController) Patterns(w http.ResponseWriter, _ *http.Request) {
	patterns := redact.JSPatterns()
	out := make([]RedactionPattern, 0, len(patterns))
	for _, pattern := range patterns {
		out = append(out, RedactionPattern{Source: pattern.Source, Flags: pattern.Flags})
	}
	envelope.WriteJSON(w, http.StatusOK, RedactionPatternsResponse{Patterns: out})
}
