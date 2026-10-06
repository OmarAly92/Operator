package github

import (
	"encoding/json"
	"errors"
	"net/http"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

func TestResolveReviewThread_SendsMutationForThread(t *testing.T) {
	f := newFakeGH(t)
	f.on(http.MethodPost, "/graphql", func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Query     string         `json:"query"`
			Variables map[string]any `json:"variables"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		if body.Query != resolveReviewThreadMutation || body.Variables["id"] != "PRRT_1" {
			t.Fatalf("body = %#v", body)
		}
		_, _ = w.Write([]byte(`{"data":{"resolveReviewThread":{"thread":{"id":"PRRT_1","isResolved":true}}}}`))
	})

	if err := newProviderForTest(t, f).ResolveReviewThread(ctx(), validMergeRequest().PR, " PRRT_1 "); err != nil {
		t.Fatal(err)
	}
}

func TestResolveReviewThread_Failures(t *testing.T) {
	for _, tc := range []struct {
		name     string
		response string
		want     error
	}{
		{"unknown thread", `{"errors":[{"type":"NOT_FOUND","message":"Could not resolve to a node with the global id of 'PRRT_1'"}]}`, ports.ErrSCMNotFound},
		{"left unresolved", `{"data":{"resolveReviewThread":{"thread":{"id":"PRRT_1","isResolved":false}}}}`, nil},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := newFakeGH(t)
			f.on(http.MethodPost, "/graphql", func(w http.ResponseWriter, _ *http.Request) {
				_, _ = w.Write([]byte(tc.response))
			})
			err := newProviderForTest(t, f).ResolveReviewThread(ctx(), validMergeRequest().PR, "PRRT_1")
			if err == nil || (tc.want != nil && !errors.Is(err, tc.want)) {
				t.Fatalf("err = %v, want %v", err, tc.want)
			}
		})
	}
}

func TestResolveReviewThread_RequiresThreadID(t *testing.T) {
	f := newFakeGH(t)
	if err := newProviderForTest(t, f).ResolveReviewThread(ctx(), validMergeRequest().PR, " "); err == nil {
		t.Fatal("want an error for an empty thread id")
	}
	if n := len(f.calls()); n != 0 {
		t.Fatalf("calls = %d, want none", n)
	}
}
