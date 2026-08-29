// Package marks decodes the warp-terminal mark protocol into block-lifecycle
// events. It mirrors the Rust crate `crates/marks` byte for byte against the
// shared vectors under protocol/vectors. See protocol/SPEC.md for the
// normative specification.
package marks

// Tier identifies which tier of the protocol a mark belongs to.
type Tier int

const (
	// TierOSC133 is the iTerm2 / VS Code / kitty / WezTerm / ghostty standard
	// tier (OSC 133 and OSC 7). It works in any shell already configured for
	// those emulators, with zero setup.
	TierOSC133 Tier = 1

	// TierExtension is the additive OSC 7000 extension this product emits
	// from its bootstrap. Decoders must still produce correct blocks when
	// only Tier 1 marks are present.
	TierExtension Tier = 2
)

// Event is a single decoded mark or related boundary event. Its shape is the
// closed vocabulary defined by protocol/SPEC.md §8.
type Event struct {
	// Kind is one of: "prompt_start", "command_start", "output_start",
	// "command_end", "cwd_changed", "extension", "alt_screen_enter",
	// "alt_screen_leave".
	Kind string

	// Tier is the tier the event originated from. Alt-screen transitions
	// report TierOSC133 (they are a sibling of OSC 133, not a third tier).
	Tier Tier

	// ExitCode is set only for "command_end" events. Its presence is a
	// bit, not a magic value — a missing ExitCode means the command
	// finished without a recorded exit code, not that the command is
	// still running (use the block state for that).
	ExitCode *int

	// Path is set only for "cwd_changed" events (OSC 7).
	Path string

	// Fields is set only for "extension" events (OSC 7000). Unknown keys
	// are preserved here for forward compatibility; known keys are kept
	// verbatim after percent-decoding. Tier-1 events leave it nil.
	Fields map[string]string
}

// Decoder is a stateful byte-level decoder. It survives across Feed calls so
// a mark split across two reads still decodes. The 4096-byte pending cap
// inside the scanner is what stops an unterminated OSC from turning the
// decoder into a permanent black hole.
type Decoder struct {
	scanner *scanner
}

// NewDecoder returns a fresh decoder. It is safe to call repeatedly; each
// decoder owns its own scanner state.
func NewDecoder() *Decoder {
	return &Decoder{
		scanner: newScanner(),
	}
}

// Feed consumes a chunk of the byte stream and returns the events it
// decodes from it. A call may return zero events (the input was a partial
// mark, plain text, or whitespace) or several. The returned slice is
// freshly allocated; the caller may retain it freely. The decoder retains
// any partial state needed to complete a sequence on the next call.
func (d *Decoder) Feed(p []byte) []Event {
	// The decoder is deliberately stateless about blocks. Whether a
	// command_end with no open block is meaningful is the block layer's
	// question (SPEC 7.5 scopes this package to finding boundaries and
	// extracting fields), and keeping that state here would make this
	// package and the Rust one disagree about where block state lives.
	return d.scanner.feed(p)
}
