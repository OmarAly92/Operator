package domain

// ReviewerHarness identifies a code-review agent. It is a separate vocabulary
// from AgentHarness on purpose: a reviewer-only tool (e.g. the Greptile CLI)
// must not become a valid worker, and a worker harness does not automatically
// become a valid reviewer. The two sets are maintained independently and only
// happen to share ids where the same tool serves both roles.
type ReviewerHarness string

// Supported reviewer harnesses. Add a reviewer-only tool here (and register its
// adapter) without widening the worker AgentHarness set.
const (
	ReviewerClaudeCode ReviewerHarness = "claude-code"
	ReviewerCodex      ReviewerHarness = "codex"
	ReviewerCopilot    ReviewerHarness = "copilot"
	ReviewerCursor     ReviewerHarness = "cursor"
	ReviewerKiloCode   ReviewerHarness = "kilocode"
	ReviewerKimchi     ReviewerHarness = "kimchi"
	ReviewerOpenCode   ReviewerHarness = "opencode"
	ReviewerKiro       ReviewerHarness = "kiro"
	ReviewerPi         ReviewerHarness = "pi"
	ReviewerQwen       ReviewerHarness = "qwen"
	ReviewerAgy        ReviewerHarness = "agy"
	ReviewerContinue   ReviewerHarness = "continue"
	ReviewerGoose      ReviewerHarness = "goose"
	ReviewerVibe       ReviewerHarness = "vibe"
	ReviewerDevin      ReviewerHarness = "devin"
	ReviewerDroid      ReviewerHarness = "droid"
	ReviewerKimi       ReviewerHarness = "kimi"
	ReviewerMuse       ReviewerHarness = "muse"
	ReviewerAmp        ReviewerHarness = "amp"
	ReviewerAider      ReviewerHarness = "aider"
	ReviewerGrok       ReviewerHarness = "grok"
	ReviewerCrush      ReviewerHarness = "crush"
	ReviewerAuggie     ReviewerHarness = "auggie"
	ReviewerCline      ReviewerHarness = "cline"
	ReviewerAutohand   ReviewerHarness = "autohand"
)

// AllReviewerHarnesses is the canonical set of reviewers Operator offers, used to
// validate a configured reviewer harness. A reviewer records its result only
// through the Operator MCP server's review_submit tool, so this is exactly the
// set whose adapter registers that server for the reviewer CLI. The other
// constants above name reviewers whose CLI cannot load it yet (no MCP client,
// or MCP config only in a file inside the worker's checkout); their adapters
// stay in adapters/reviewer, unregistered, until they are wired.
var AllReviewerHarnesses = []ReviewerHarness{
	ReviewerClaudeCode,
	ReviewerCodex,
	ReviewerCopilot,
	ReviewerKiloCode,
	ReviewerOpenCode,
	ReviewerQwen,
	ReviewerAmp,
	ReviewerAuggie,
}

// RetiredReviewerHarnesses were offered before reviewers recorded results
// through the Operator MCP server. A project config or session may still name
// one: it stays valid to store, so an unrelated config edit does not fail, and
// is skipped when choosing the reviewer.
var RetiredReviewerHarnesses = []ReviewerHarness{
	ReviewerCursor,
	ReviewerKimchi,
	ReviewerKiro,
	ReviewerPi,
	ReviewerAgy,
	ReviewerContinue,
	ReviewerGoose,
	ReviewerVibe,
	ReviewerDevin,
	ReviewerDroid,
	ReviewerKimi,
	ReviewerMuse,
	ReviewerAider,
	ReviewerGrok,
	ReviewerCrush,
	ReviewerCline,
	ReviewerAutohand,
}

// IsRetired reports whether h names a reviewer Operator no longer offers.
func (h ReviewerHarness) IsRetired() bool {
	for _, k := range RetiredReviewerHarnesses {
		if h == k {
			return true
		}
	}
	return false
}

// IsKnown reports whether h is one of the supported reviewer harnesses.
func (h ReviewerHarness) IsKnown() bool {
	for _, k := range AllReviewerHarnesses {
		if h == k {
			return true
		}
	}
	return false
}
