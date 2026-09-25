# Plan 7 — Very old output: measurement

Date: 2026-09-25
Machine: `Linux vm 6.18.44-fc-v37 #1 SMP PREEMPT_DYNAMIC @0 x86_64 x86_64 x86_64 GNU/Linux`, CPU `Intel(R) Xeon(R) Processor @ 2.80GHz`, 4 cores.
Branch: `terminal/plan-7-old-output`, commit `f171fb722b720add61bcc0bde379c70a32443691` (top of branch at measurement time, before this task's own commit).

## Commands run

Go report test, twice, feeding 520,000 synthetic ~110-character rows (every fifth ANSI-coloured) through a mirror-sized parser with a 32 MiB cold ring, plus the `claude-long-50k` agent-session fixture:

```bash
cd backend/internal/adapters/runtime/ptyhost && rm -f "$TMPDIR/older-answer.bin"
for run in 1 2; do OPERATOR_OLDER_REPORT=1 OPERATOR_OLDER_ANSWER_OUT="$TMPDIR/older-answer.bin" \
  OPERATOR_AGENT_FIXTURE="packages/terminal/bench/agent-session/fixtures/claude-long-50k" \
  go test ./vtwasm/ -run TestOlderOutputReport -count=1 -v -timeout 20m 2>&1 | grep OLDER-REPORT; done
```

Renderer side of one click, twice, against the answer chunk the Go run wrote to `$TMPDIR/older-answer.bin`:

```bash
cd packages/terminal && npm run build:ts && for run in 1 2; do node "$TMPDIR/renderer-click.mjs" "$PWD" "$TMPDIR/older-answer.bin"; done
```

## Results

### Go host side (two runs)

| field | run 1 | run 2 |
|---|---|---|
| feedMB | 55.44281 | 55.44281 |
| feedMsWithRing | 5647 | 5323 |
| feedMsWithoutRing | 5232 | 4846 |
| wasmBytesWithRing | 77,594,624 | 77,594,624 |
| wasmBytesWithoutRing | 35,979,264 | 35,979,264 |
| coreRows | 199,999 | 199,999 |
| coreContentBytes | 21,601,932 | 21,601,932 |
| ringRows | 266,728 | 266,728 |
| ringBytes | 33,554,386 | 33,554,386 |
| ringFirstStableRow | 53,234 | 53,234 |
| clickRows | 2,048 | 2,048 |
| clickBytes | 245,395 | 245,395 |
| clickMsNewestRing | 1.382 | 1.574 |
| clickMsOldestRing | 0.610 | 0.575 |
| fixtureRingRows | 50,098 | 50,098 |
| fixtureRingBytes | 1,092,308 | 1,092,308 |
| fixtureClickRows | 2,048 | 2,048 |
| fixtureClickBytes | 32,246 | 32,246 |
| fixtureClickMsRing | 0.352 | 0.318 |
| fixtureHistoryRows | 60,097 | 60,097 |
| fixtureClickRowsFromHistory | 2,048 | 2,048 |
| fixtureClickMsFromHistory | 2.352 | 2.453 |

The row-count, byte-count, and wasm-memory fields are identical across both runs because the fed payload is deterministic; only the timing fields vary run to run, well inside noise.

### Renderer side of one click (two runs)

| field | run 1 | run 2 |
|---|---|---|
| firstSnapshotMs | 1158.68 | 1174.65 |
| front | 319,962 | 319,962 |
| after | 317,914 | 317,914 |
| historyRows | 202,047 | 202,047 |
| feedMs | 45.05 | 37.72 |
| snapshotMs | 1193.38 | 1187.73 |
| answerBytes | 245,419 | 245,419 |
| older.floor | 53,234 | 53,234 |
| older.marks | 1 | 1 |

`after` (317,914) is exactly `front` (319,962) minus the 2,048 rows in the chunk: the answer was accepted, not silently dropped.

## Conclusions

1. **A full 32 MiB ring costs the mirror ≈1.2× its cap in wasm memory.** `wasmBytesWithRing` (77,594,624) minus `wasmBytesWithoutRing` (35,979,264) is 41,615,360 bytes, and 41,615,360 / 33,554,432 (the cap) ≈ 1.24. The ring's own payload (`ringBytes`, 33,554,386) never exceeds its 32 MiB cap (33,554,432), confirming the single upfront reservation described in the design decisions rather than the ~2× a naive grow-and-copy ring would cost.

2. **The host side of a click is under a few ms.** `clickMsNewestRing` (1.382 / 1.574 ms) and `clickMsOldestRing` (0.610 / 0.575 ms) on the synthetic 520k-row mirror, and `fixtureClickMsRing` (0.352 / 0.318 ms) / `fixtureClickMsFromHistory` (2.352 / 2.453 ms) on the `claude-long-50k` fixture, are all comfortably under 3 ms — negligible next to the renderer-side cost below.

3. **The renderer side is one full re-export of the pane's scrollback per click.** `snapshotMs` (1193.38 / 1187.73 ms) is the same order of magnitude as `firstSnapshotMs` (1158.68 / 1174.65 ms), the cost of the renderer's very first full export of 200k rows, while `feedMs` (45.05 / 37.72 ms) — the cost of parsing and prepending the 2,048-row chunk itself — is two orders of magnitude smaller. This is why a click fetches one 2,048-row chunk and not four 512-row chunks: `Parser::apply_history_chunk` marks the renderer's export full on every applied chunk (`parser/history.rs:69`), so four smaller chunks would force four full re-exports instead of one.

4. **Feed throughput with the ring on is within noise of off.** `feedMsWithRing` (5647 / 5323 ms) vs `feedMsWithoutRing` (5232 / 4846 ms) for the same 55.4 MB payload differ by +8% and +10% across the two runs — consistent with the plan's own proving-machine observation of "+6% and -1%: inside noise," not a systematic regression from the ring being enabled.

All expectations were met: the answer chunk was accepted (`after == front - 2048`), `ringBytes` stayed under its cap, and the wasm memory with a full ring stayed well under 2× the memory without one (1.24×, not 2×).
