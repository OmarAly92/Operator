# Task 9 noise outliers: which take, why

Run: `packages/mobile/build/glass_lab/runs/noise-2b1`. Takes are under
`takes/<scene>/<case>/<n>/` (video.mp4, ready.png, settled.png, bare/, timing.json, driver.log);
the ten pair analyses that `case_noise` (lab.py:181) wrote are under `<scene>/<case>/pair-<i>-<j>/result.json`.
The per-take numbers below come from re-running `analyze.window` and `shapes.capture` on copies of
the take folders in a scratch dir (`/private/tmp/claude-501/.../scratchpad/takes`) so that
`track.extract` did not rewrite the run's `shapes/` folders. Nothing in the run or in `noise.json` was changed.

## Verdict

All three outliers come from **take 3**, which is in **session 2** (after the reboot). In every case
the cause is a **capture artifact**: `simctl io recordVideo` (record.py:21) delivered no frames for
the start of the animation, then flushed a burst of frames 1.7 to 6.7 ms apart. The animation states
in the frames match the other takes' states exactly, but their timestamps are squeezed together, so the
progress curve looks much faster than it was. The native animation did not vary.

Two things about the artifact matter:
- `align.stalls` does not see it. Stalls start counting at `first + 2` (align.py:61), and the hole is
  at the first frame of the event. The burst that follows has gaps that are too small, not too large.
- The touch window comes out zero-length in take 3 (`[t, t]`) because the marker frames fall into
  the same squeezed span.

Every pair that includes take 3 is the worst pair. No pair without take 3 comes close.

## Pair values (block.step1e0.progress, from pair-*/result.json)

| case | pairs with take 3: t10_90 / rms | pairs without take 3: max t10_90 / max rms |
|---|---|---|
| materialize light-stripes | 75, 75, 75, 66.7 ms / 0.087-0.090 | 8.3 ms / 0.0164 |
| bouncy dark-photo-reduce-motion | 100 ms each / 0.114-0.116 | 0 ms / 0.0129 |
| bouncy dark-stripes-reduce-motion | 33.3 ms each / 0.047-0.049 | 0 ms / 0.0144 |

Per-take progress features (t10_90, settle):
- light-stripes: takes 0,1,2 = 125 / 208.3; take 3 = **50 / 141.7**; take 4 = 116.7 / 208.3
- bouncy dark-photo-rm: takes 0-2,4 = 108.3 / 158-175; take 3 = **8.3 / 33.3**
- bouncy dark-stripes-rm: takes 0-2,4 = 100 / 158.3; take 3 = **66.7 / 116.7**

## Frame evidence (block region, video time in seconds)

### 1. material.materialize / light-stripes, take 3 (started 04:03:20, the first take after the reboot)
Touch window `[16.765, 16.765]` (zero length). Event onset 16.837. first_frame gap 68.3 ms (takes 0-2: 26.7-28.3).
```
16.7683  prog 0.965 (rest)
16.8367  +68.3 ms  prog 0.904
16.8417  +5.0      prog 0.348   <- 0.80, 0.62, 0.50 missing (takes 0-2 show them 15-18 ms apart)
16.8450  +3.3      prog 0.348   (duplicate)
16.8467  +1.7      prog 0.245
16.8533  +6.7      prog 0.245   (duplicate)
16.8617  +8.3      prog 0.160
16.8783  +16.7     prog 0.100   ... normal 16.7 ms cadence from here on
```
The 0.9 to 0.1 span is about 42 ms here; take 2 takes about 117 ms to cover the same states
(0.903, 0.800, 0.618, 0.502, 0.347, 0.263, 0.160, 0.116, 0.058, at about 16.7 ms each).
From 0.160 on, the state values (w/h/luma) are the same as take 2's. Stall list: [28.3 ms].

### 2. material.materialize.bouncy / dark-photo-reduce-motion, take 3 (started 05:14:31)
Touch window `[17.647, 17.647]`. Event onset 17.647. first_frame gap **396.7 ms**, with progress already 0.58 at the first frame.
```
17.2500           prog 0.990 (rest; normal VFR idle gap before)
17.6467 +396.7 ms prog 0.412  <- the whole 0.99 to 0.41 run (about 6 frames) never recorded
17.6483 +1.7      prog 0.058
17.6517 +3.3      prog 0.028  (repeats at +3.3, +5.0, +3.3)
17.6667 +3.3      prog 0.009 ... normal cadence from about 17.70
```
Take 2 covers 0.99 to 0.05 in about 130 ms at a 15-20 ms cadence. Take 3 shows only 0.41 and 0.058.

### 3. material.materialize.bouncy / dark-stripes-reduce-motion, take 3 (started 05:11:30)
Touch window `[18.357, 18.357]`. Event onset 18.357. first_frame gap **406.7 ms**, with progress 0.34 at the first frame.
```
17.9500           prog 1.044 (rest)
18.3567 +406.7 ms prog 0.711  <- 1.004, 0.877 missing
18.3617 +5.0      prog 0.546  (repeats at +1.7, +3.3, +5.0)
18.3750 +3.3      prog 0.399
18.3817 +6.7      prog 0.398
18.3950 +13.3     prog 0.282 ... normal cadence
```
The states (0.546, w251 h89, luma 155.4; 0.282, luma 161.5; 0.129, w74) are identical to take 2's.
Take 4 of this case also has a 36.7 ms stall at prog 0.37 to 0.175. Pairs with take 4 stay at
t10_90 0 and rms at most 0.0144, so that stall does not move the noise.

## Four-take noise (takes 0,1,2,4; information only, nothing written)

| case | t10_90_ms | progress.rms | progress.settle_ms |
|---|---|---|---|
| materialize light-stripes | 8.3 (was 75) | 0.0164 (was 0.090) | 0 (was 66.7) |
| bouncy dark-photo-reduce-motion | 0 (was 100) | 0.0129 (was 0.116) | 16.7 (was 141.7) |
| bouncy dark-stripes-reduce-motion | 0 (was 33.3) | 0.0144 (was 0.049) | 0 (was 41.7) |

Take 3 inflates every step1e0 measure in these three cases, not only progress. Five-take values
(which match noise.json) against four-take values:
- light-stripes: delay_ms 45 / 20; width.peak_ms 83.3 / 25; width.response_pct 96.8 / 6.2;
  luma.settle_ms 75 / 8.3; progress.sharpness 0.105 / 0.018
- bouncy dark-photo-rm: width/height/luma/progress settle and peak 125-142 / 8-17; progress.sharpness 0.384 / 0.197
- bouncy dark-stripes-rm: delay_ms 35 / 10; width.response_pct 38.7 / 10.4; cx.response_pct 27.6 / 0;
  peak and settle 42-50 / 0-25

step3e0 (the second toggle) is unaffected in all three take-3 recordings: first_frame gap 16.7-18.3 ms,
with t10_90 in line with the other takes.

## Open question
Other session-2 takes may have the same burst at their step1 event without becoming an outlier,
because a smaller hole shifts the curve less. Bouncy dark-photo-rm take 4 starts with gaps of 3.3, 5.0
and 6.7 ms but keeps every state, for example. This investigation checked only these three cases.
A first_frame gap well above about 30 ms, or a zero-length touch window, would flag such a take.
