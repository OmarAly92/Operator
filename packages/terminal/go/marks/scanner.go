package marks

// pendingCap is the hard ceiling on an in-flight OSC payload. Past this we
// abandon the sequence rather than buffer it forever — the spec says a
// decoder "MUST handle an OSC that never terminates" by giving up and
// resuming on the next byte. The plan's "things that are easy to get wrong"
// section calls this out by name.
const pendingCap = 4096

const (
	esc       byte = 0x1B
	bel       byte = 0x07
	bracket   byte = ']'
	backslash byte = '\\'
	csi       byte = '['
	question  byte = '?'
)

type state int

const (
	stateGround state = iota
	// AfterEsc: just saw ESC; the next byte decides whether it is an OSC
	// (']') or a CSI ('[') or some other sequence we ignore.
	stateAfterEsc
	// Osc: inside an OSC payload, terminated by BEL or `ESC \`.
	stateOsc
	// OscSawEsc: we just saw ESC inside an OSC; the next byte decides
	// whether it is a real ST ('\\') or an abort (anything else).
	stateOscSawEsc
	// CsiPrivate: inside a DEC private-mode CSI sequence (we only model
	// `?1049h`/`l`).
	stateCsiPrivate
)

type scanner struct {
	state            state
	pending          []byte
	privateQuestion  bool
	privateDigits    []byte
}

func newScanner() *scanner {
	return &scanner{
		state:         stateGround,
		pending:       make([]byte, 0, 64),
		privateDigits: make([]byte, 0, 4),
	}
}

func (s *scanner) feed(bytes []byte) []Event {
	events := make([]Event, 0, 4)
	for _, b := range bytes {
		s.step(b, &events)
	}
	return events
}

func (s *scanner) step(b byte, events *[]Event) {
	switch s.state {
	case stateGround:
		if b == esc {
			s.state = stateAfterEsc
		}
	case stateAfterEsc:
		switch b {
		case bracket:
			s.pending = s.pending[:0]
			s.state = stateOsc
		case csi:
			s.privateQuestion = false
			s.privateDigits = s.privateDigits[:0]
			s.state = stateCsiPrivate
		default:
			// Some other escape (e.g. `ESC c` for full reset). Drop it
			// and resume scanning — a stray ESC never opens an OSC.
			s.state = stateGround
		}
	case stateOsc:
		switch {
		case b == bel:
			s.flushOsc(events)
			s.state = stateGround
		case b == esc:
			// Defer the ST-or-abort decision to the next byte.
			s.state = stateOscSawEsc
		default:
			s.pushPending(b)
		}
	case stateOscSawEsc:
		if b == backslash {
			// Real ST — close the OSC.
			s.flushOsc(events)
			s.state = stateGround
		} else {
			// A bare ESC inside an OSC is what shells send when they
			// abort a half-written prompt. The
			// `malformed-truncated-sequence` vector is the regression:
			// drop the OSC payload, then re-process the new byte as
			// if we had just seen ESC. That way a `]` following the
			// abort opens a fresh OSC, matching the expected output.
			s.pending = s.pending[:0]
			s.state = stateAfterEsc
			s.step(b, events)
		}
	case stateCsiPrivate:
		switch {
		case !s.privateQuestion && b == question && len(s.privateDigits) == 0:
			s.privateQuestion = true
		case s.privateQuestion && (isDigit(b) || b == ';'):
			if b != ';' {
				s.privateDigits = append(s.privateDigits, b)
			}
		case b == 'h':
			if s.privateQuestion && string(s.privateDigits) == "1049" {
				*events = append(*events, Event{Kind: "alt_screen_enter", Tier: TierOSC133})
			}
			s.state = stateGround
		case b == 'l':
			if s.privateQuestion && string(s.privateDigits) == "1049" {
				*events = append(*events, Event{Kind: "alt_screen_leave", Tier: TierOSC133})
			}
			s.state = stateGround
		default:
			// Some other CSI we don't model. Abort cleanly.
			s.state = stateGround
		}
	}
}

func (s *scanner) pushPending(b byte) {
	s.pending = append(s.pending, b)
	if len(s.pending) > pendingCap {
		// Spec: "give up on the unterminated sequence and resume on the
		// next byte." This is the only allocation bound we need.
		s.pending = s.pending[:0]
		s.state = stateGround
	}
}

func (s *scanner) flushOsc(events *[]Event) {
	// An empty OSC payload is meaningless; both decoders must ignore it.
	payload := s.pending
	s.pending = make([]byte, 0, 64)
	if e, ok := decodeOsc(payload); ok {
		*events = append(*events, e)
	} else if f, ok := decodeExtension(payload); ok {
		*events = append(*events, Event{Kind: "extension", Tier: TierExtension, Fields: f})
	}
}

// decodeOsc decodes a Tier-1 OSC payload. The payload is the bytes between
// `ESC ]` and the terminator (BEL or `ESC \`), so `OSC 133 ; A` arrives here
// as `"133;A"`. Returns the event and true for recognised marks, false
// otherwise (unknown subcommand, empty payload, or Tier-2 prefix — the
// extension decoder handles that).
func decodeOsc(payload []byte) (Event, bool) {
	if len(payload) == 0 {
		return Event{}, false
	}
	split := indexByte(payload, ';')
	var command, rest []byte
	if split < 0 {
		command = payload
		rest = nil
	} else {
		command = payload[:split]
		rest = payload[split+1:]
	}

	switch string(command) {
	case "133":
		return decodeOsc133(rest)
	case "7":
		return decodeOsc7(rest)
	}
	// Any other OSC (including `7000` for Tier 2) returns false here so
	// the scanner falls through to the extension decoder.
	return Event{}, false
}

func decodeOsc133(rest []byte) (Event, bool) {
	// The subcommand is the first byte of `rest`. We accept only
	// single-byte subcommands in Phase 1a: A, B, C, and D. Anything else
	// is ignored (recovery row 7).
	if len(rest) == 0 {
		return Event{}, false
	}
	sub := rest[0]
	tail := rest[1:]
	switch sub {
	case 'A':
		return Event{Kind: "prompt_start", Tier: TierOSC133}, true
	case 'B':
		return Event{Kind: "command_start", Tier: TierOSC133}, true
	case 'C':
		return Event{Kind: "output_start", Tier: TierOSC133}, true
	case 'D':
		// `D;<exit>` is the form with an exit code; bare `D` is the
		// "missing exit" form (spec §6).
		var exit *int
		if len(tail) > 0 && tail[0] == ';' {
			if n, ok := parseInt(string(tail[1:])); ok {
				exit = &n
			}
		}
		return Event{Kind: "command_end", Tier: TierOSC133, ExitCode: exit}, true
	}
	return Event{}, false
}

func decodeOsc7(rest []byte) (Event, bool) {
	// `OSC 7 ; file://host/path` — the path is the part after the third
	// `/` in the URL, matching the conventional `file://host/path` form.
	path, ok := pathFromFileURL(string(rest))
	if !ok {
		return Event{}, false
	}
	return Event{Kind: "cwd_changed", Tier: TierOSC133, Path: path}, true
}

func pathFromFileURL(url string) (string, bool) {
	const prefix = "file://"
	if !hasPrefix(url, prefix) {
		return "", false
	}
	after := url[len(prefix):]
	// Drop the host segment, if any (`file://host/path` -> `/path`).
	if slash := indexByteString(after, '/'); slash >= 0 {
		return after[slash:], true
	}
	return after, true
}

// decodeExtension decodes a Tier-2 (OSC 7000) payload. The payload is the
// bytes between `ESC ]` and `ESC \`, so `OSC 7000 ; v=1 ; id=block-001 ; …`
// arrives here as `"7000;v=1; id=block-001; …"`. The pair separator is a
// literal `; ` (semicolon then space) per SPEC §4.1.
//
// Returns the fields map and true for a parseable mark whose `v` major
// version is the one this decoder understands (1). A higher major version
// returns false per SPEC §4.2 — the mark is ignored in its entirety.
func decodeExtension(payload []byte) (map[string]string, bool) {
	const prefix = "7000;"
	if !hasPrefix(string(payload), prefix) {
		return nil, false
	}
	pairsStr := string(payload[len(prefix):])

	fields := make(map[string]string)
	versionSeen := false
	versionRejected := false

	for _, pair := range splitPairs(pairsStr) {
		if pair == "" {
			continue
		}
		eq := indexByteString(pair, '=')
		if eq < 0 {
			continue
		}
		rawKey := pair[:eq]
		rawValue := pair[eq+1:]
		value := percentDecode(rawValue)

		if rawKey == "v" && !versionSeen {
			// The version check is what gates a "higher major" mark. We
			// read this key *first* (per SPEC §4.2) so a future v=2 mark
			// is dropped before any other key is parsed. If we can't
			// parse the version at all, we still try to extract the keys
			// we know — the spec only requires whole-mark rejection for a
			// *higher* major.
			versionSeen = true
			if n, ok := parseUint(value); ok && n > 1 {
				versionRejected = true
			}
		}

		fields[rawKey] = value
	}

	if versionRejected {
		return nil, false
	}
	return fields, true
}

// splitPairs splits a Tier-2 payload on the literal `; ` (semicolon then
// space) per SPEC §4.1. A trailing `;` without a space leaves an empty
// trailing pair, which the caller filters out.
func splitPairs(s string) []string {
	var out []string
	start := 0
	for i := 0; i+1 < len(s); i++ {
		if s[i] == ';' && s[i+1] == ' ' {
			out = append(out, s[start:i])
			start = i + 2
			i++ // skip the space on the next iteration
		}
	}
	out = append(out, s[start:])
	return out
}

// percentDecode is a minimal percent-decoder for the byte alphabet the
// protocol allows. Any other byte is passed through verbatim — the encoder
// is responsible for the encoding, and a malformed escape is the encoder's
// bug, not the decoder's. This is intentionally not a full RFC 3986
// implementation.
func percentDecode(input string) string {
	out := make([]byte, 0, len(input))
	for i := 0; i < len(input); i++ {
		if input[i] == '%' && i+2 < len(input) {
			if hi, ok1 := hexDigit(input[i+1]); ok1 {
				if lo, ok2 := hexDigit(input[i+2]); ok2 {
					out = append(out, hi*16+lo)
					i += 2
					continue
				}
			}
		}
		out = append(out, input[i])
	}
	return string(out)
}

func hexDigit(c byte) (byte, bool) {
	switch {
	case c >= '0' && c <= '9':
		return c - '0', true
	case c >= 'a' && c <= 'f':
		return c - 'a' + 10, true
	case c >= 'A' && c <= 'F':
		return c - 'A' + 10, true
	}
	return 0, false
}

// indexByte is a local equivalent of bytes.IndexByte to keep this file's
// imports to the standard library only.
func indexByte(b []byte, c byte) int {
	for i, x := range b {
		if x == c {
			return i
		}
	}
	return -1
}

func indexByteString(s string, c byte) int {
	for i := 0; i < len(s); i++ {
		if s[i] == c {
			return i
		}
	}
	return -1
}

func hasPrefix(s, prefix string) bool {
	return len(s) >= len(prefix) && s[:len(prefix)] == prefix
}

func isDigit(b byte) bool {
	return b >= '0' && b <= '9'
}

func parseInt(s string) (int, bool) {
	if s == "" {
		return 0, false
	}
	n := 0
	neg := false
	start := 0
	if s[0] == '-' {
		neg = true
		start = 1
	} else if s[0] == '+' {
		start = 1
	}
	if start == len(s) {
		return 0, false
	}
	for i := start; i < len(s); i++ {
		c := s[i]
		if c < '0' || c > '9' {
			return 0, false
		}
		n = n*10 + int(c-'0')
	}
	if neg {
		n = -n
	}
	return n, true
}

func parseUint(s string) (uint64, bool) {
	if s == "" {
		return 0, false
	}
	var n uint64
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c < '0' || c > '9' {
			return 0, false
		}
		n = n*10 + uint64(c-'0')
	}
	return n, true
}
