# Task 20d report (Steps 7, 8, 9)

HEAD 58ab57e0c, simulator 708879DD. `lab.py build operator` ok (exit 0). Loads (uptime): build 0:28 load 10.4; run batch start 0:31 load 43 (heavy), ghost probes 1:47-1:48 load 10-13. No driver crashes (no driver.log with only the invocation line), no reruns. Accessibility defaults after: ReduceMotionEnabled 0 (other two keys absent). `lab.py report` run on all nine.

## Step 7 (still_check, outputs in task-20d-still-<scene>.txt)
| scene | 2A run | new run | missing | worse | byte-identical Flutter frames |
|---|---|---|---|---|---|
| regular | 20261002-200447 | 20261006-003104 | 0 | 0 | 20 (20 scene, case and frame triples compared) |
| clear | 20261002-201611 | 20261006-004222 | 0 | 0 | 8 (8 scene, case and frame triples compared) |
| tinted | 20261002-151504 | 20261006-004700 | 0 | 0 | 12 (12 scene, case and frame triples compared) |
| edge | 20261002-202042 | 20261006-005342 | 0 | 0 | 0 (12 scene, case and frame triples compared) |
| reduce-transparency | 20261002-202731 | 20261006-010032 | 0 | 0 | 20 (20 scene, case and frame triples compared) |
| increase-contrast | 20261002-203837 | 20261006-011154 | 0 | 0 | 20 (20 scene, case and frame triples compared) |
| tabbar-rest | 20261002-205000 | 20261006-012309 | 0 | 0 | 16 (16 scene, case and frame triples compared) |
| button-press | 20261002-205855 | 20261006-013200 | 0 | 0 | 4 (4 scene, case and frame triples compared) |
| navbar-inline | 20261002-210140 | 20261006-013445 | 0 | 0 | 12 (12 scene, case and frame triples compared) |

All nine: missing 0, worse 0.

REGRESSION CANDIDATE: material.edge: 0 of 12 Flutter frames byte-identical (all 6 edge cases x ready/settled differ; max channel difference 16 to 32). Measures all unchanged (mad/luminance equal, pass -> pass; the two soft light-scroll mad fails are 4.07 -> 4.07). Examined automatic/dark-scroll ready: the whole difference is 1334 pixels in x 976-1159, y 183-318 (1206x2622), the thin ring around the top-right "Edit" glass pill; 429 pixels differ by more than 4. Signed sum 114 (582 positive, 708 negative pixels), no net shift: zero-mean speckle on the rim, content and label identical. ready vs settled are identical within each run (old and new), so it is deterministic per run, not frame jitter. Crop (2A | new | diff x8): scratchpad/crop.png. Likely cause to check: the changed edge-light/rim uniform path (c7f1c9b41) at a scroll-edge pill; the other seven Flutter-only scenes' glass is identical. Not triaged further.

Other scenes: every non-identical item is on an unchanged Flutter frame (flutter difference 0.0) with native frame difference listed in each file (ruling 28); e.g. button.press native max difference 229.0, clear dark-photo 2.0, tabbar.rest light-stripes 2.0, increase-contrast light-white 2.0, navbar.inline 0.0. Measures equal old -> new in all lines.

## Step 8 (rim_check, ramp3.0 = table/ramp3.0, runs 20261005-233131 normal, 20261005-234750 reduce motion)
Flutter rim depth (pt) 0.67-1.0 at every visibility, within 1/3 pt of its depth at 1 from 0.3 up in all four cases, in both runs: PASS (rim well below visibility 1 matches).
Native normal: dark-photo 1.0 rest, 14.5/24/24 at 0.3/0.5/0.7; dark-stripes 1.0 -> 5/5/5; light-photo 1.0 -> 10/24/24; light-stripes 1.67 -> 5.5/5.33/5.33.
Native Reduce Motion: 1.0 (light-stripes 1.67) -> 5.0-5.33 at 0.3-0.7 in all four.
Matches the prototype read. Files: task-20d-rim-normal.txt, task-20d-rim-rm.txt.

## Step 9 (ghost probes)
- container: build/glass_lab/ghost/20261006-014735/removal.png (22 frames). Ten rows viewed: "Glass" label stays in place, fades with the glass, no blink; background shapes and glass fade out smoothly. Mean difference from ready 2.29, 2.93, 5.04, 7.80, 10.09, 11.90, 13.30 ... 16.95, monotone, no jump.
- standalone (Overlay): build/glass_lab/ghost/20261006-014805/removal.png (21 frames). Same picture; values 2.28, 2.89, 5.05, 7.76, 10.08, 11.87, 13.29 ... 16.95, monotone, no jump.
Both match the prototype.
