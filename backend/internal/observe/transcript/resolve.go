// Package transcript projects a live session's native provider transcript into
// block events. Hooks are the status channel of the blocks view; this is the
// body channel — what the agent actually said, thought, ran and got back.
//
// It deliberately sits beside the usage observer rather than inside it. Both
// read the same provider files, for unrelated reasons and on independent
// cursors; coupling usage accounting to block projection would make either
// one's failure the other's.
package transcript

import (
	"context"
	"os"
	"path/filepath"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

// Resolver turns a session record into the absolute path of the provider
// transcript that session is currently writing.
type Resolver struct {
	agents ports.AgentResolver
}

// NewResolver builds a resolver over the daemon's per-session agent registry.
func NewResolver(agents ports.AgentResolver) *Resolver {
	return &Resolver{agents: agents}
}

// Path returns the transcript path for a session, or "" when the harness has no
// adapter, the adapter exposes no config directory, or no readable transcript
// exists yet. The hook-reported path is externally supplied, so every candidate
// must be a regular file inside the provider's own config directory before it
// is opened.
func (r *Resolver) Path(ctx context.Context, rec domain.SessionRecord) string {
	if r == nil || r.agents == nil {
		return ""
	}
	agent, found := r.agents.Agent(rec.Harness)
	if !found || agent == nil {
		return ""
	}
	provider, ok := agent.(ports.AgentNativeSessionConfigProvider)
	if !ok {
		return ""
	}
	configDir, err := provider.NativeSessionConfigDir(ctx, nil)
	if err != nil || strings.TrimSpace(configDir) == "" {
		return ""
	}
	if path := containedPath(ctx, rec.Metadata.NativeTranscriptPath, configDir); path != "" {
		return path
	}
	locator, ok := agent.(ports.AgentTranscriptLocator)
	nativeID := strings.TrimSpace(rec.Metadata.AgentSessionID)
	if !ok || nativeID == "" {
		return ""
	}
	located, ok, err := locator.LocateTranscript(ctx, ports.NativeSessionRef{
		NativeSessionID: nativeID,
		ConfigDir:       configDir,
	})
	if err != nil || !ok {
		return ""
	}
	return containedPath(ctx, located, configDir)
}

func containedPath(ctx context.Context, path, configDir string) string {
	if ctx.Err() != nil {
		return ""
	}
	path = strings.TrimSpace(path)
	if path == "" || !filepath.IsAbs(path) || strings.TrimSpace(configDir) == "" {
		return ""
	}
	realConfigDir, err := filepath.EvalSymlinks(filepath.Clean(configDir))
	if err != nil {
		return ""
	}
	realPath, err := filepath.EvalSymlinks(filepath.Clean(path))
	if err != nil {
		return ""
	}
	rel, err := filepath.Rel(realConfigDir, realPath)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return ""
	}
	info, err := os.Stat(realPath)
	if err != nil || !info.Mode().IsRegular() {
		return ""
	}
	return realPath
}
