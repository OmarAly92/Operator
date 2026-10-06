package pr

import (
	"context"
	"errors"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type fakeActionStore struct {
	pr domain.PullRequest
	ok bool
}

func (f *fakeActionStore) GetPR(context.Context, string) (domain.PullRequest, bool, error) {
	return f.pr, f.ok, nil
}

type fakeSCMAction struct {
	observation ports.SCMObservation
	review      ports.SCMReviewObservation
	mergeErr    error
	request     ports.SCMMergeRequest
	mergeCalls  int
}

func (f *fakeSCMAction) FetchPullRequests(context.Context, []ports.SCMPRRef) ([]ports.SCMObservation, error) {
	return []ports.SCMObservation{f.observation}, nil
}

func (f *fakeSCMAction) FetchReviewThreads(context.Context, ports.SCMPRRef) (ports.SCMReviewObservation, error) {
	return f.review, nil
}

func (f *fakeSCMAction) MergePullRequest(_ context.Context, request ports.SCMMergeRequest) (ports.SCMMergeResult, error) {
	f.mergeCalls++
	f.request = request
	return ports.SCMMergeResult{MergeCommitSHA: "merge-sha"}, f.mergeErr
}

func mergeableActionFixture() (domain.PullRequest, *fakeSCMAction) {
	pr := domain.PullRequest{
		URL:          "https://github.com/acme/widgets/pull/42",
		Number:       42,
		Provider:     "github",
		Host:         "github.com",
		Repo:         "acme/widgets",
		HeadSHA:      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		Mergeability: domain.MergeMergeable,
	}
	scm := &fakeSCMAction{observation: ports.SCMObservation{
		Fetched:      true,
		PR:           ports.SCMPRObservation{URL: pr.URL, Number: pr.Number, HeadSHA: pr.HeadSHA},
		CI:           ports.SCMCIObservation{Summary: string(domain.CIPassing), HeadSHA: pr.HeadSHA},
		Mergeability: ports.SCMMergeabilityObservation{State: string(domain.MergeMergeable), Mergeable: true},
	}}
	return pr, scm
}

func TestActionServiceMerge_GuardsAndSquashMergesExactHead(t *testing.T) {
	pr, scm := mergeableActionFixture()
	svc := NewActionService(ActionDeps{Store: &fakeActionStore{pr: pr, ok: true}, Reader: scm, Merger: scm})
	result, err := svc.Merge(context.Background(), MergeRequest{PRID: "42", PRURL: pr.URL, ExpectedHeadSHA: pr.HeadSHA})
	if err != nil {
		t.Fatal(err)
	}
	if result.PRNumber != 42 || result.Method != "squash" || result.MergeCommitSHA != "merge-sha" {
		t.Fatalf("result = %#v", result)
	}
	if scm.mergeCalls != 1 || scm.request.ExpectedHeadSHA != pr.HeadSHA || scm.request.Method != ports.SCMMergeSquash {
		t.Fatalf("request = %#v, calls = %d", scm.request, scm.mergeCalls)
	}
}

func TestActionServiceMerge_FailsClosedForStaleHeadOrReadiness(t *testing.T) {
	pr, scm := mergeableActionFixture()
	svc := NewActionService(ActionDeps{Store: &fakeActionStore{pr: pr, ok: true}, Reader: scm, Merger: scm})
	_, err := svc.Merge(context.Background(), MergeRequest{PRID: "42", PRURL: pr.URL, ExpectedHeadSHA: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"})
	if !errors.Is(err, ErrPRHeadChanged) || scm.mergeCalls != 0 {
		t.Fatalf("stale head error = %v, calls = %d", err, scm.mergeCalls)
	}

	pr, scm = mergeableActionFixture()
	scm.observation.CI.Summary = string(domain.CIPending)
	svc = NewActionService(ActionDeps{Store: &fakeActionStore{pr: pr, ok: true}, Reader: scm, Merger: scm})
	_, err = svc.Merge(context.Background(), MergeRequest{PRID: "42", PRURL: pr.URL, ExpectedHeadSHA: pr.HeadSHA})
	if !errors.Is(err, ErrPRPreconditions) || scm.mergeCalls != 0 {
		t.Fatalf("pending CI error = %v, calls = %d", err, scm.mergeCalls)
	}
}

func TestActionServiceMerge_MapsProviderConflict(t *testing.T) {
	pr, scm := mergeableActionFixture()
	scm.mergeErr = ports.ErrSCMHeadChanged
	svc := NewActionService(ActionDeps{Store: &fakeActionStore{pr: pr, ok: true}, Reader: scm, Merger: scm})
	_, err := svc.Merge(context.Background(), MergeRequest{PRID: "42", PRURL: pr.URL, ExpectedHeadSHA: pr.HeadSHA})
	if !errors.Is(err, ErrPRHeadChanged) {
		t.Fatalf("error = %v", err)
	}
}

type fakeThreadResolver struct {
	resolved []string
	err      error
}

func (f *fakeThreadResolver) ResolveReviewThread(_ context.Context, _ ports.SCMPRRef, threadID string) error {
	if f.err != nil {
		return f.err
	}
	f.resolved = append(f.resolved, threadID)
	return nil
}

func reviewThreadsFixture() ports.SCMReviewObservation {
	return ports.SCMReviewObservation{Threads: []ports.SCMReviewThreadObservation{
		{ID: "T_1", Comments: []ports.SCMReviewCommentObservation{{ID: "C_1"}, {ID: "C_2"}}},
		{ID: "T_2", Resolved: true, Comments: []ports.SCMReviewCommentObservation{{ID: "C_3"}}},
		{ID: "T_3", Comments: []ports.SCMReviewCommentObservation{{ID: "C_4"}}},
	}}
}

func TestActionServiceResolveComments_SelectsUnresolvedThreads(t *testing.T) {
	for _, tc := range []struct {
		name string
		ids  []string
		want []string
	}{
		{"every unresolved thread", nil, []string{"T_1", "T_3"}},
		{"by comment id", []string{"C_2"}, []string{"T_1"}},
		{"by thread id", []string{"T_3"}, []string{"T_3"}},
		{"thread named twice resolves once", []string{"C_1", "C_2", "T_1"}, []string{"T_1"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			pr, scm := mergeableActionFixture()
			scm.review = reviewThreadsFixture()
			resolver := &fakeThreadResolver{}
			svc := NewActionService(ActionDeps{Store: &fakeActionStore{pr: pr, ok: true}, Reader: scm, Resolver: resolver})
			result, err := svc.ResolveComments(context.Background(), ResolveRequest{PRID: "42", PRURL: pr.URL, CommentIDs: tc.ids})
			if err != nil {
				t.Fatal(err)
			}
			if result.Resolved != len(tc.want) || !equalStrings(resolver.resolved, tc.want) {
				t.Fatalf("resolved %d %v, want %v", result.Resolved, resolver.resolved, tc.want)
			}
		})
	}
}

func TestActionServiceResolveComments_Errors(t *testing.T) {
	pr, _ := mergeableActionFixture()
	for _, tc := range []struct {
		name    string
		store   *fakeActionStore
		review  ports.SCMReviewObservation
		request ResolveRequest
		want    error
	}{
		{"missing url", &fakeActionStore{pr: pr, ok: true}, reviewThreadsFixture(), ResolveRequest{PRID: "42"}, ErrInvalidPR},
		{"untracked pr", &fakeActionStore{}, reviewThreadsFixture(), ResolveRequest{PRID: "42", PRURL: pr.URL}, ErrPRNotFound},
		{"number mismatch", &fakeActionStore{pr: pr, ok: true}, reviewThreadsFixture(), ResolveRequest{PRID: "7", PRURL: pr.URL}, ErrPRNotFound},
		{"unknown comment", &fakeActionStore{pr: pr, ok: true}, reviewThreadsFixture(), ResolveRequest{PRID: "42", PRURL: pr.URL, CommentIDs: []string{"C_3", "C_9"}}, ErrCommentsNotFound},
		{"all resolved", &fakeActionStore{pr: pr, ok: true}, ports.SCMReviewObservation{}, ResolveRequest{PRID: "42", PRURL: pr.URL}, ErrNothingToResolve},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, scm := mergeableActionFixture()
			scm.review = tc.review
			resolver := &fakeThreadResolver{}
			svc := NewActionService(ActionDeps{Store: tc.store, Reader: scm, Resolver: resolver})
			_, err := svc.ResolveComments(context.Background(), tc.request)
			if !errors.Is(err, tc.want) {
				t.Fatalf("err = %v, want %v", err, tc.want)
			}
			if len(resolver.resolved) != 0 {
				t.Fatalf("resolved %v, want nothing", resolver.resolved)
			}
		})
	}
}

func TestActionServiceResolveComments_ReportsPartialProgress(t *testing.T) {
	pr, scm := mergeableActionFixture()
	scm.review = reviewThreadsFixture()
	resolver := &fakeThreadResolver{err: errors.New("boom")}
	svc := NewActionService(ActionDeps{Store: &fakeActionStore{pr: pr, ok: true}, Reader: scm, Resolver: resolver})
	result, err := svc.ResolveComments(context.Background(), ResolveRequest{PRID: "42", PRURL: pr.URL})
	if err == nil || result.Resolved != 0 {
		t.Fatalf("result = %#v, err = %v", result, err)
	}
}

func equalStrings(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
