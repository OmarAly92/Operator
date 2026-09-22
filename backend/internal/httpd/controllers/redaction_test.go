package controllers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRedactionPatternsReturnsEveryBuiltinShape(t *testing.T) {
	recorder := httptest.NewRecorder()
	(&RedactionController{}).Patterns(recorder, httptest.NewRequest(http.MethodGet, "/api/v1/redaction/patterns", nil))
	if recorder.Code != http.StatusOK {
		t.Fatalf("status %d", recorder.Code)
	}
	var body RedactionPatternsResponse
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(body.Patterns) == 0 {
		t.Fatal("no patterns")
	}
	for _, pattern := range body.Patterns {
		if pattern.Source == "" {
			t.Fatalf("empty source: %+v", body.Patterns)
		}
	}
}
