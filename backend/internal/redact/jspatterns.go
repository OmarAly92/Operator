package redact

// Pattern is one secret shape in the form a JavaScript RegExp takes: Go's
// (?i) inline flag has no ECMAScript equivalent, so it travels as a flag.
type Pattern struct {
	Source string `json:"source"`
	Flags  string `json:"flags"`
}

// jsPattern is the JavaScript form of the built-in shape at the same index in
// builtinPatterns. The only way to hand a Go regex to JavaScript is to carry
// its source deliberately, so the two lists are written side by side and a test
// fails if one of them grows alone.
type jsPattern struct {
	Source string
	Flags  string
}

var builtinJSPatterns = []jsPattern{
	{Source: `\bAKIA[0-9A-Z]{16}\b`, Flags: "i"},
	{Source: `\bgh[pousr]_[A-Za-z0-9]{20,}\b`, Flags: ""},
	{Source: `\bsk-[A-Za-z0-9_\-]{20,}\b`, Flags: ""},
	{Source: `(bearer\s+)[A-Za-z0-9._\-]{16,}`, Flags: "i"},
	{Source: `((?:api[_\-]?key|secret|token|password)\s*[:=]\s*)[^\s"']{8,}`, Flags: "i"},
	{Source: `([a-z][a-z0-9+.\-]*://[^\s:/@]+:)[^\s@]+(@)`, Flags: ""},
}

// JSPatterns returns the built-in shapes for a client that does its own
// masking. User patterns from redact-patterns.txt are deliberately not
// included: they are Go syntax the user wrote for this daemon, and a client
// that cannot compile one would silently mask less than the daemon does.
func JSPatterns() []Pattern {
	out := make([]Pattern, 0, len(builtinJSPatterns))
	for _, pattern := range builtinJSPatterns {
		out = append(out, Pattern{Source: pattern.Source, Flags: pattern.Flags})
	}
	return out
}
