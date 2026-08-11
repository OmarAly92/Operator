package daemon

import (
	"errors"
	"log/slog"

	trackergithub "github.com/OmarAly92/operator/backend/internal/adapters/tracker/github"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func newGitHubTracker() (ports.Tracker, error) {
	return trackergithub.New(trackergithub.Options{Token: trackergithub.EnvTokenSource{EnvVars: []string{"OPERATOR_GITHUB_TOKEN"}}})
}

func logTrackerDisabled(logger *slog.Logger, err error) {
	if errors.Is(err, trackergithub.ErrNoToken) {
		logger.Warn("tracker issue prompt enrichment disabled: no usable GitHub token", "err", err)
	} else {
		logger.Warn("tracker issue prompt enrichment disabled: GitHub tracker setup failed", "err", err)
	}
}
