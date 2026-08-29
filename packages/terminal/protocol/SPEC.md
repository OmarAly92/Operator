# The mark protocol

Status: normative, frozen for Phase 1a.
Source: `docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md` §7.

This document is the single source of truth for the byte sequences the
`@operator/terminal-*` packages consume as block-lifecycle marks. Both decoders
(`crates/marks` in Rust and `go/marks` in Go) MUST be conformant against the
vectors under `vectors/`. A change to this document means changing the vectors
first, which fails both decoders at once. That is the point.

The keywords "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD",
"SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be
interpreted as described in RFC 2119.

---

## 1. Where the protocol lives

`packages/terminal/protocol/` is a top-level directory containing:

- `SPEC.md` — this document;
- `README.md` — the one-page index of what the directory is;
- `vectors/*.json` — conformance vectors: input byte stream plus expected
  decoded events;
- `fuzz-corpus/*.bin` — raw byte seeds for the fuzz target.

Both decoders are tested against the same vectors. The decoders never reach
into each other's code; they only read the vectors and the spec.

## 2. One encoding, chosen once

The protocol uses two tiers sharing the OSC container (`ESC ]`):

- **Tier 1** — `OSC 133 ; A|B|C|D` and `OSC 7 ; file://…`; works with any
  shell already configured for iTerm2 / VS Code / kitty / WezTerm / ghostty,
  including over ssh and inside containers. Zero setup.
- **Tier 2** — `OSC 7000 ; key=value ; key=value ST`, one key=value
  encoding, values percent-encoded. Our additive extension; consumed only
  from sessions that source our bootstrap.

There MUST NOT be a second extension encoding. Tier 2 is strictly additive:
a decoder that sees only Tier 1 MUST still produce correct, usable blocks,
and no code path may require a Tier-2 mark to close a block. Unknown keys
are the forward-compatibility story; they are ignored individually, never
fatally.

## 3. Tier 1 — OSC 133 and OSC 7

### 3.1 Sequences

| Sequence | Meaning | What we get |
| --- | --- | --- |
| `OSC 133 ; A ST` | prompt start | block boundary |
| `OSC 133 ; B ST` | prompt end / command start | command text start |
| `OSC 133 ; C ST` | command executed / output start | output start |
| `OSC 133 ; D ; <exit> ST` | command finished | exit code |
| `OSC 7 ; file://host/path ST` | cwd | prompt row cwd |

`ST` is shown in this table for compactness. By §3.2 every OSC (including
`OSC 7`) also accepts BEL as a terminator.

`<exit>` is an ASCII decimal integer. Its presence is optional — see §6.

A Tier-1 block has `BlockSource::Osc133`. Command text is read from the grid
between `B` and `C`; it MAY be imperfect (wrapped lines, a prompt that
repaints). That is acceptable and is exactly why Tier 2 exists.

### 3.2 Terminators

Every OSC in this protocol MUST be accepted with either terminator:

- **BEL** — the byte `0x07`;
- **ST** — the two-byte sequence `ESC \` (i.e. `0x1B 0x5C`).

A decoder that handles only one of these will miss half the shells in the
wild. The vectors under `vectors/osc133-st-terminator.json` and
`vectors/osc133-happy-path.json` together pin both forms.

## 4. Tier 2 — OSC 7000

### 4.1 Encoding

```
OSC 7000 ; key=value ; key=value ST
```

- The leading `OSC 7000 ;` is fixed text; the first key follows immediately
  after the semicolon.
- Pairs are separated by `;` (semicolon). A single ASCII space immediately
  after a separator is accepted and ignored, so both `k=v;k=v` and
  `k=v; k=v` are valid encodings.
- Each value MUST be percent-encoded per RFC 3986 §2.1. The character
  alphabet for the unencoded form is the bytes that are safe in a pty
  stream: `[A-Za-z0-9._~/:@!$&'()*+,;=-]`. Every other byte — including
  space — MUST be percent-encoded.
- `ST` is the terminator (BEL is not accepted for Tier 2; Tier 2 marks are
  emitted by our bootstrap, which uses ST).

### 4.2 Version key

The mark MUST carry a `v=<n>` key. Decoders:

- MUST accept any `v` they understand;
- MUST ignore a mark whose major version is higher than they understand,
  in its entirety, without partial parsing;
- MUST NOT fail on a mark with a higher major version.

Adding a new key is a non-breaking change. Raising the major version of
the protocol is a breaking change. There is no in-protocol signal for
"this is a minor version above mine"; that is the only forward-incompatible
step, and it is reserved for a future plan that picks the new behaviour.

### 4.3 Keys defined in Phase 1a

The following keys are defined in Phase 1a. A decoder MUST extract every
key it understands and ignore every key it does not. Keys not listed here
MAY be added in a later phase by amending this table; the addition of a
key is a non-breaking change because unknown keys are ignored.

| Key | Meaning | Type |
| --- | --- | --- |
| `v` | protocol version; required, integer | integer |
| `id` | block id, opaque, stable across resize/reattach | string |
| `cmd` | exact command text | string |
| `cwd` | working directory, percent-encoded | string |
| `branch` | git branch name, percent-encoded | string |
| `exit` | exit code; presence/absence is a bit, not a magic value (see §6) | integer |
| `start_ms` | millisecond Unix epoch at command start | integer |
| `end_ms` | millisecond Unix epoch at command end | integer |

### 4.4 Line-editor ownership keys

| Key | Meaning | Value |
| --- | --- | --- |
| `input-ready` | the shell's line editor is idle and accepting input | `1` |
| `input-released` | a program has taken over the tty | `1` |

These are the explicit signal that replaces Warp's 50ms activation timer
(spec §3.5, §10.2). A decoder MUST surface them as the `input_ready` and
`input_released` events in §8. A mark carrying both MUST be surfaced as
`input_released` only: the safe state is "a program owns the tty".

They remain strictly additive. A decoder that ignores them still produces
correct blocks, and no block lifecycle transition depends on either key.

## 5. Tier 2 — events emitted

Tier 2 is consumed when `v` is present and its major version is the
one the decoder understands (§4.2). Tier 2 contributes the same
lifecycle events Tier 1 does, plus the fields in §4.3. A Tier-2 block
has `BlockSource::Extension`.

## 6. Exit code presence

Whether a block carries an exit code is encoded as a presence bit, not as
a sentinel value. Concretely:

- For `OSC 133 ; D ; <exit> ST`, the exit code is the parameter after `D`
  if it parses as a decimal integer; otherwise the block is `Finished`
  with no exit code.
- For Tier 2, the `exit` key is present iff the value was provided. A
  missing `exit` key is `None`; a present but unparseable `exit` key
  is `None` (and the decoder SHOULD log a warning, MUST NOT crash).
- An absent exit code is meaningful: it means "the command finished but
  the shell did not record an exit code", not "the command is still
  running". Use `BlockState` to distinguish the two.

## 7. Tolerant parsing — the recovery table

This table is normative. `crates/marks` and `go/marks` MUST both implement
it, and the vectors under `vectors/` MUST cover every row. The table is
copied verbatim from `docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md`
§7.4.

| Situation | Behavior |
| --- | --- |
| `A` with a block already open | close the open block as `Abandoned`, start a new one |
| `B` with no preceding `A` | start a block at the current row, `source` from the mark tier |
| `C` with no preceding `B` | command text is empty, output starts here |
| `D` with no open block | ignore |
| `D` with a missing exit parameter | `exit_code: None`, state `Finished` |
| `A` immediately followed by `A` | first closes `Abandoned` (this is the fish case, §3.2) |
| unknown OSC 133 subcommand | ignore, do not close or open anything |
| unknown OSC 7000 key | ignore that key, keep the rest of the mark |
| malformed / truncated sequence | ignore the sequence, never drop subsequent bytes |
| output arriving with no marks at all | accumulate into a `Synthetic` block |

**MUST NOT:** assume any mark is paired. `crates/warp_terminal/src/local_tty/shell.rs:691-694`
is the failure mode that produced this rule.

## 8. Event vocabulary

A vector's `events` array lists mark events in the order a conforming
decoder MUST emit them. The `kind` and `tier` values are the closed
vocabulary. A decoder MUST NOT emit an event whose `kind` is not in this
list; this is the wire-level contract.

| `kind` | Meaning |
| --- | --- |
| `prompt_start` | OSC 133 `A`; opens a block |
| `command_start` | OSC 133 `B`; command text begins |
| `output_start` | OSC 133 `C`; output begins |
| `command_end` | OSC 133 `D[; exit]`; command finished, with optional exit code |
| `cwd_changed` | OSC 7; working directory update |
| `extension` | OSC 7000 mark; carries the extension fields |
| `input_ready` | shell line editor is idle and accepting input |
| `input_released` | a program has taken over the tty |
| `alt_screen_enter` | DCS / private-mode enter of the alternate screen |
| `alt_screen_leave` | leave of the alternate screen |

`alt_screen_enter` and `alt_screen_leave` are not marks in the protocol's
narrow sense but they are events a decoder must surface so the daemon and
the renderer can suspend block capture between them. The vectors do not
cover alt-screen transitions; the existing alt-screen handling in
`vt-core` is the reference. They are listed here so a decoder does not
introduce a second event vocabulary for them.

## 9. Decoder contract

A conformant decoder:

1. consumes a stream of bytes that may split any sequence across any read
   boundary;
2. emits the events in §8 in source order, with no duplicates and no drops
   outside the recovery rules in §7;
3. never panics, never aborts, never allocates without bound on any byte
   input;
4. passes every vector under `vectors/`;
5. passes the fuzz target seeded with `fuzz-corpus/`, including unpaired
   marks, marks split across read boundaries, and marks interleaved with
   SGR and alt-screen switches.

A decoder that passes the vectors but panics on a split-across-reads mark
is a decoder that will fail in production, because PTY reads split
wherever they like. The split-read test under
`fuzz-corpus/mark-split-across-read-boundary.bin` is the regression for
this.
