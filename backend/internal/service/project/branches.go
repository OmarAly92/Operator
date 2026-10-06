package project

import (
	"context"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/apierr"
)

func (m *Service) Branches(ctx context.Context, id domain.ProjectID) (Branches, error) {
	if err := validateProjectID(id); err != nil {
		return Branches{}, err
	}
	row, ok, err := m.store.GetProject(ctx, string(id))
	if err != nil {
		return Branches{}, apierr.Internal("PROJECT_LOAD_FAILED", "Failed to load project")
	}
	if !ok || !row.ArchivedAt.IsZero() {
		return Branches{}, apierr.NotFound("PROJECT_NOT_FOUND", "Unknown project")
	}
	if row.Kind.WithDefault() != domain.ProjectKindSingleRepo {
		return Branches{}, apierr.Invalid("BRANCHES_UNSUPPORTED_PROJECT_KIND", "Branches can only be listed for a single-repo project", nil)
	}
	if m.branches == nil {
		return Branches{}, apierr.Internal("BRANCHES_UNAVAILABLE", "Branch listing is not configured")
	}
	listing, err := m.branches.ListBranches(ctx, row.Path)
	if err != nil {
		return Branches{}, apierr.Internal("BRANCHES_LOAD_FAILED", "Failed to list branches")
	}
	out := Branches{Current: listing.Current, Branches: make([]Branch, 0, len(listing.Branches))}
	for _, b := range listing.Branches {
		out.Branches = append(out.Branches, Branch{Name: b.Name, CheckedOutAt: b.CheckedOutAt, IsMainCheckout: b.IsMainCheckout})
	}
	return out, nil
}
