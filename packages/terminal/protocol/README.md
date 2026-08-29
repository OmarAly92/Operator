# `packages/terminal/protocol/`

The mark protocol that block-aware decoders in both `crates/marks` (Rust) and
`go/marks` (Go) consume. The protocol is the single source of truth for
block-lifecycle marks; the two decoders are independent implementations that
read the same vectors and are tested against the same spec.

## Contents

| File | What it is |
| --- | --- |
| `SPEC.md` | The normative protocol document. Tiers, terminators, keys, reserved keys, recovery table. |
| `vectors/*.json` | Conformance vectors: input byte stream plus expected decoded events. 16 files, one per §7.4 recovery-table row plus both terminator forms and Tier 2. |
| `fuzz-corpus/*.bin` | Raw byte seeds for the fuzz target: every vector's decoded input plus five hazard files. |

## The contract

A decoder that is "done" against this protocol:

1. **MUST pass every vector under `vectors/`.** No skipped file, no skipped event.
2. **MUST pass the fuzz target seeded with `fuzz-corpus/`.** No panic, no abort, no
   unbounded allocation on any byte input.
3. **MUST handle reads that split any sequence across any read boundary.** PTY reads
   split wherever they like, and a decoder that passes the vectors but panics on a
   split-read input is not done. The `mark-split-across-read-boundary.bin` seed is
   the regression for this — it embeds a `133;D` whose `ESC ]133` lives in one
   read and `;D;0` BEL in the next.
4. **MUST handle marks interleaved with other escape sequences** — SGR colour
   changes inside a `B`/`C` pair, alt-screen enter/leave around a block. The
   `marks-interleaved-with-sgr.bin` and `marks-interleaved-with-alt-screen.bin`
   seeds are the regressions.
5. **MUST handle an OSC that never terminates.** The
   `osc-that-never-terminates.bin` seed is the regression — the decoder gives
   up on the unterminated sequence and resumes on the next byte.
6. **MUST handle adversarial density.** The `sixtyfour-kib-esc-bracket.bin` seed
   is 64 KiB of repeated `ESC ]` pairs with no payload. A decoder that does
   not bound its OSC buffer will allocate 64 KiB per call; over a session that
   is a leak.

## Changing the protocol

Changing the protocol means changing the vectors first. The procedure is:

1. Edit `SPEC.md` to describe the new shape.
2. Add or update the affected vectors under `vectors/`. The new vectors are
   normative — the spec describes them in prose, the vectors pin them in
   data.
3. Commit the spec and vector change as one commit.
4. Both decoders will now fail. Each decoder's task is to make the tests
   pass against the new vectors. Neither decoder is allowed to "be lenient"
   in a way that disagrees with the spec; if the spec says the decoder
   must accept X, both decoders accept X.

A vector that does not match the spec is a spec bug; a decoder that disagrees
with a vector is a decoder bug. The two together are unambiguous.

## File format

Each vector JSON file has the shape:

```json
{
  "name": "osc133-happy-path",
  "input": "\u001b]133;A\u0007$ \u001b]133;B\u0007ls -la\u001b]133;C\u0007total 0\n\u001b]133;D;0\u0007",
  "events": [
    { "kind": "prompt_start", "tier": 1 },
    { "kind": "command_start", "tier": 1 },
    { "kind": "output_start", "tier": 1 },
    { "kind": "command_end", "tier": 1, "exitCode": 0 }
  ]
}
```

A variation using the ST terminator (`\u001b\\\`) instead of BEL:

```json
{
  "name": "osc133-st-terminator",
  "input": "\u001b]133;A\u001b\\\$ \u001b]133;B\u001b\\\ls -la\u001b]133;C\u001b\\\hi\n\u001b]133;D;0\u001b\\\",
  "events": [
    { "kind": "prompt_start", "tier": 1 },
    { "kind": "command_start", "tier": 1 },
    { "kind": "output_start", "tier": 1 },
    { "kind": "command_end", "tier": 1, "exitCode": 0 }
  ]
}
```

- `input` is a JSON string containing the raw bytes the decoder consumes.
  Control bytes are written as JSON unicode escapes (`\u001b` for ESC,
  `\u0007` for BEL, `\\` for ST, `\n` for LF) so the file stays printable and diffable
  in a normal text editor or diff tool. The decoder decodes the string to
  bytes before feeding the parser.
- `events` lists mark events only. Literal text between marks is not an event.
  `kind` is one of `prompt_start`, `command_start`, `output_start`,
  `command_end`, `cwd_changed`, `extension`, `alt_screen_enter`,
  `alt_screen_leave`. `tier` is 1 or 2. `exitCode` is an integer and is
  present only on `command_end` events that carry an exit code; its
  absence is meaningful (see `SPEC.md` §6).
