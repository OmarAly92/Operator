
### Task 12: Native references N3, N4, N6 and the held-out sizes, after a fresh boot

**Files:**
- Create: `docs/liquid_glass/02b-motion/research/execution-2b3/references.txt`, `references.json`

**Interfaces:**
- Consumes: Tasks 2 and 3's scenes and the scripted take check in `lab.py run` (Task 3), `R/native_questions.py`.
- Produces: native references, every take clean under the take check (ruling 16), for `material.drag.fast`, `material.drag.out`, `material.drag.far`, `material.drag.up`, `material.neighbours.0`, `.10`, `.40`, `material.press.circle44` and `material.press.120x250` (the two held-out sizes, ruling 8), `material.press.250x150` and `material.press.300x250` (fitted) and `material.press.capsule36` (their cases: light and dark `photo`, ruling 19), and the Reduce Motion cases of `material.interactive` (four), `material.drag.fast` (two) and `material.drag.out` (two: spec N6's drag that leaves the glass under Reduce Motion, R7). 32 cases; at the prototype's capture-hole rate (40–55 % of attempts, ruling 16) about 70 attempts, 55 minutes of recording.

```bash
cd /Users/omaraly/development/AI/Operator-2b3/packages/mobile
R=/Users/omaraly/development/AI/Operator-2b3/docs/liquid_glass/02b-motion/research/proto-2b3
E=/Users/omaraly/development/AI/Operator-2b3/docs/liquid_glass/02b-motion/research/execution-2b3
mkdir -p $E
```

- [ ] **Step 1: Build, reboot, check the press.**

```bash
df -h /Users/omaraly
python3 tool/glass_lab/harness/lab.py build all
python3 -c "import sys; sys.path.insert(0, 'tool/glass_lab/harness'); import sim, build; u = sim.device(); sim.status_bar(u); [sim.install_backdrops(u, b, build.backdrops()) for b in (build.NATIVE_BUNDLE, build.EXAMPLE_BUNDLE)]"
python3 tool/glass_lab/harness/lab.py reboot
python3 tool/glass_lab/harness/lab.py run material.interactive --app native --appearance dark --backdrop photo
```

Expected: `build/glass_lab/runs/<that run>/material.interactive/dark-photo/native/takecheck.json` lists no failure (its press reads within 20 % of 1.0 s, gotcha 49). Three failed attempts in a row mean a stale or loaded simulator: reboot and check again. Nothing else runs on the Mac from here to the end of Step 2.

- [ ] **Step 2: Record.** One command at a time, `run_in_background`; `run` re-records a press take that fails the take check up to twice and keeps the failed ones under `<case>/excluded/`:

```bash
for s in material.drag.fast material.drag.out material.drag.far material.drag.up material.neighbours.0 material.neighbours.10 material.neighbours.40 material.press.circle44 material.press.250x150 material.press.300x250 material.press.120x250 material.press.capsule36; do python3 tool/glass_lab/harness/lab.py run $s --app native || { echo "STOP $s"; exit 1; }; done
for s in material.interactive material.drag.fast material.drag.out; do python3 tool/glass_lab/harness/lab.py run $s --app native --a11y reduce-motion || { echo "STOP $s"; exit 1; }; done
```

A case whose kept take still fails (`takecheck.json` lists a failure) is recorded again on its own (`--appearance`, `--backdrop`) after a reboot. Count the takes, kept and excluded, whose only failure is a lost-frame gap in the onset window (90 ms after a touch-down, ruling 16) and write the count with the attempts into `references.txt`: more than one in ten means the window flags native's own cadence; stop and report to the main session.

- [ ] **Step 3: Read the answers.** `python3 $R/native_questions.py --harness tool/glass_lab/harness --out $E/references.json <scene>=<case>/native ... > $E/references.txt`, one argument per case. Check, per case: (ruling 3) every drag keeps the glass grown until touch-up, with `material.drag.fast` |`stretch`| ≤ 0.017 and `centre` ≤ 0.6 pt, and write `stretch` and `centre` of `drag.out`, `drag.far` and `drag.up` into `references.txt` (D6); (ruling 4) every `right` glass `glow_peak` < 3 inside its pinned rect and `grow_w` < 1 pt, and on both appearances its rest box (`shape_rest` in `references.json`) covers the pinned rect (F8); (ruling 10) every Reduce Motion `grow_w` < 1 pt and `glow_peak` ≥ 3, and the Reduce Motion `drag.out` keeps its light until touch-up. **If a case shows the opposite (a release before touch-up, a neighbour that lights or scales, growth under Reduce Motion), stop and report to the main session.**

- [ ] **Step 4: Commit** (`git add docs/liquid_glass/02b-motion/research/execution-2b3`; message `test(glass-lab): native N3, N4, N6 and held-out size references after a fresh boot` with the session's attribution line).

### Task 13: Noise floors for every press scene (L8)

**Files:**
- Modify: `tool/glass_lab/noise.json` (written by `lab.py repeat` only)
- Create: `docs/liquid_glass/02b-motion/research/execution-2b3/noise-moved.txt`, `noise-sources.txt`

**Interfaces:**
- Consumes: the archive's `runs/noise-2b1` (2B.1's five takes per case for `material.interactive` and `material.press.{circle58,138x53,250x44,300x120,360x200}`), the scripted take check and the leverage stop in `lab.py repeat` (Task 3).
- Produces: floors with the press measures for the 2B.1 scenes (2B.1's takes that pass today's take check, topped up to five clean takes per case) and for the new scenes and the Reduce Motion cases of Task 12. Ruling 16 found 13 of 30 sampled 2B.1 press takes flagged, so about 52 of the 120 2B.1 takes are replaced; 38 new cases need 190 clean takes. At the prototype's rate that is about 420 attempts: **about 5 h of recording and 3 h of analysis**, over two sessions with a reboot between; the archive copy is 8.6 GB.

```bash
NOISE=$PWD/build/glass_lab/runs/noise-2b1
RUN=$PWD/build/glass_lab/runs/noise-2b3
```

- [ ] **Step 1: Copy the 2B.1 takes (never move or write the archive).**

```bash
df -h /Users/omaraly
test ! -e $NOISE && mkdir -p build/glass_lab/runs && cp -R /Users/omaraly/development/AI/glass-lab-runs/2b1/runs/noise-2b1 build/glass_lab/runs/
test -d $NOISE && test ! -L $NOISE && echo "copy, not a link"
git show HEAD:packages/mobile/tool/glass_lab/noise.json > /tmp/noise-before.json
```

`lab.case_noise` repoints the copy's dangling pair links itself (2B.2 Task 9).

- [ ] **Step 1b: Before each recording group, check the disk.** `df -h /Users/omaraly`. Under 40 GB, stop and report. To make room a task may remove only the analysis frame caches (`overview/`, `shapes/`, `marker/`) of takes in this execution's own run folders (`$NOISE`, `$RUN`, `build/glass_lab/runs/2026*` made in this execution) that have already been analysed (their `result.json` or `noise.json` entry exists): `find <run> -type d \( -name overview -o -name shapes -o -name marker \) -prune -exec rm -rf {} +`, after listing what it will remove. Never a `video.mp4`, `ready.png`, `settled.png`, `bare/`, `takecheck.json` or any recording, never anything under `/Users/omaraly/development/AI/glass-lab-runs/` or the prototype's runs; anything else needs the main session's yes. Write the space before and after into `$E/noise-moved.txt`.

- [ ] **Step 2: Session 1.** Reboot and check the press (Task 12 Step 1). For each of the six 2B.1 scenes, one at a time: `repeat <scene> --times 0 --into $NOISE` (it checks every take on disk, moves the failing ones to `$NOISE/excluded/` with their reasons, and recomputes); then for each case with fewer than five takes left, `repeat <scene> --times <5 − left> --appearance <a> --backdrop <b> --into $NOISE` (it records until that many pass). For the new scenes: `repeat <scene> --times 3 --into $RUN` for `material.drag.{fast,out,far,up}`, `material.neighbours.{0,10,40}` and `material.press.{circle44,250x150,300x250,120x250,capsule36}`, and with `--a11y reduce-motion` for `material.interactive`, `material.drag.fast` and `material.drag.out`. `repeat` exits non-zero on a static repeatability failure and on a case that could not record enough clean takes in three times as many attempts; each stops the task: report the scene, case and the takes' reasons. It also exits non-zero **when one take sets a time limit above 3 × the median of the pairs without it** (the leverage stop, D3), which Step 2b handles. The leverage check runs only on a case with five or more takes, so it cannot fire on session 1's three-take new cases.

- [ ] **Step 2b: When the leverage stop fires.** `repeat` has written every other case's floor and **nothing for the stopped case**: its entry in `noise.json` is the one it had before (none for a new case), and the message and the case's `noise-sources.json` (`leverage`) name the take, the measure, its pair noise and the siblings' median. Then:
  1. open the take's frames around the measure's event and say what is wrong with it (a squeeze the take check missed, a stall, a touch late);
  2. move the take (never delete it): `mkdir -p <run>/excluded/<scene>/<case> && mv <run>/takes/<scene>/<case>/<n> <run>/excluded/<scene>/<case>/<n>`, and write the reason into `<run>/excluded/<scene>/<case>/<n>/reason.txt` (`leverage: <measure> <pair noise> ms against a median of <m> ms; <what the frames show>`);
  3. reboot (`lab.py reboot`) and check the press (Task 12 Step 1);
  4. record one replacement and recompute that case: `repeat <scene> --times 1 --appearance <a> --backdrop <b> --into <run>`;
  5. report the take, the measure, its limit before and after, and the replacement in `$E/noise-moved.txt`.
  A second stop on the same case stops the task: report to the main session. The leverage stop is pinned by `test_the_leverage_check_waits_for_five_takes` and `test_a_stopped_case_keeps_its_old_floor_and_repeat_exits_after_writing_the_others` (Task 3).

- [ ] **Step 3: Reboot, check the press, session 2:** the new scenes' loops again with `--times 2` into `$RUN`, so each new case has five clean takes from two boots. The 2B.1 scenes' takes already span 2B.1's two sessions.

- [ ] **Step 4: What moved.** For every scene, compare `noise.json` with `/tmp/noise-before.json` and write each changed or added value to `$E/noise-moved.txt`; copy each case's `noise-sources.json` into `$E/noise-sources.txt` with its scene and case. Expected for the 2B.1 scenes: an old value changes only where an excluded take had set it (name each such value and its take).

- [ ] **Step 5: Commit** `noise.json` and the evidence (`test(glass-lab): press floors from clean takes only`).

### Task 14: Refit the press on every clean press take and rewrite `ios27_press.dart`

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/motion/ios27_press.dart` (by `pressfit.py fit --write` only), `packages/ios_liquid_glass/README.md` (its numbers)
- Create: `docs/liquid_glass/02b-motion/research/execution-2b3/press-series.json`, `glow-profile.json`, `pressfit.json`

- [ ] **Step 1: The series.** Copy N1 and N2 from the archive (`runs/20261006-085522`, `-085825`, `-191235`) if they are not yet in `build/glass_lab/runs`, then run `python3 $R/native_questions.py --harness tool/glass_lab/harness --out $E/press-series.json` with one argument per N1 and N2 case, per clean noise take of the six 2B.1 scenes, of `material.press.250x150`, `material.press.300x250` and `material.press.capsule36` (`$NOISE/takes/...`, `$RUN/takes/...`), and per Reduce Motion take of `material.interactive` (`$RUN/takes/material.interactive/*-reduce-motion/*`). `native_questions.py` records each take's check; `pressfit` leaves out every take that fails it or has a holed first press, and `material.press.circle44` (held out, ruling 8).
- [ ] **Step 2: The profile and the fit.**

```bash
python3 tool/glass_lab/harness/pressfit.py profile <the key of every clean Reduce Motion material.interactive dark-photo take in press-series.json> --series $E/press-series.json --runs <the folder above their run folders> --out $E/glow-profile.json
python3 tool/glass_lab/harness/pressfit.py fit $E/press-series.json --profile $E/glow-profile.json --out $E/pressfit.json > $E/pressfit.txt
grep PROBLEM $E/pressfit.txt || echo "no problems"
```

The profile is the median, ring by ring, of every clean Reduce Motion `dark-photo` take's rings (R8; the prototype's is six takes'), each read at its own `glow_drop`, from `press-series.json`, never typed. **Stop rule (D13, the user's decision):** the refit reads Tasks 12 and 13's fresh data (about 12 sizes) and chooses the form by the same rule, every measured size within the 1 pt threshold first, then leave-one-size-out. If `grep PROBLEM` names `no growth law form keeps every measured height within 1.0 pt`, **stop**: `pressfit` has written nothing to `ios27_press.dart`; report to the main session with the per-size residuals of every form (`law.forms.*.residuals` in `$E/pressfit.json`), and do not go on to Step 3. Otherwise expected: `no problems`. `pressfit` refuses a law or sigma on its grid edge, more than 25 % of the per-take spring fits on their grid edge, a Reduce Motion cut from fewer than five presses, and a missing fit (Review Focus 5). Compare `$E/pressfit.json` with `R/pressfit.json` in the report (the chosen form and constants, springs, cut per size, hold and swell per size, sigma). The law is fitted on every normal `photo` take's plateau, holed or not (ruling 8); the form is chosen by the 1 pt rule, then leave-one-size-out among the qualifying forms; report `law.forms.*` (each form's constants, residuals per size and leave-one-size-out RMS) and `law.separated`.

- [ ] **Step 3: Write, rebuild, gate, judge the held-out size.** `pressfit.py fit ... --write`, `lab.py build all`, the package, example and app gates; correct the README's numbers. Then judge `material.press.circle44` and `material.press.120x250` (both apps, both `photo` cases) against the new table and report their `grow_w`, `grow_h` and light measures as **held out**: they were not fitted. Also report the chosen form and the law's residual at every fitted size (`law.residuals` in `pressfit.json`), and whether the qualifying forms are separated (`law.separated`): each within 1 pt, or `pressfit` has refused to write. The prototype's held-out results are in ruling 8.
- [ ] **Step 4: Commit** (`feat(ios_liquid_glass): press table refitted on every clean native press take`).

### Task 14b: NOT TO RUN (the user chose D6 A). Kept only as the record of option B

**Do not run this task, and do not write its tests or code.** The user chose D6 A on 2026-10-09: the lean is a fix wave after 2B.3. This block is separable and nothing depends on it: no other task's patch, test, run or count includes it, and Task 15 forecasts `material.drag.{out,up,far}` failing `stretch` and `centre`. It was never prototyped (the prototype measured native's lean, ruling 3, and built none of it), so it is a sketch for that fix wave, not a step of this plan; Task 16 copies it into `todo-2b3.md`.

**Files:**
- Modify: `tool/glass_lab/harness/pressfit.py` (a `lean` command, `fit_lean`, and three constants in the table it writes), `tests/test_pressfit.py`
- Modify: `packages/ios_liquid_glass/lib/src/motion/glass_press.dart` (a lean spring), `glass_press_widgets.dart` (the pointer's position against the shape; `debugGlassPress` also returns the lean), `lib/src/liquid_glass.dart` (the drawn rect stretched and moved by the lean), `ios27_press.dart` (by `pressfit.py lean --write` only), `test/motion/glass_press_test.dart`

**The model.** While a press's finger is outside the glass's shape, at a distance `d` pt from the shape along the unit direction `u` from the glass's centre to the finger, the glass's centre moves toward the finger by `S × (1 − exp(−d / L))` pt and its width-to-height ratio changes by `E × (1 − exp(−d / L))` along `u` (wider for a horizontal `u`, taller for a vertical one, area kept), on the growth spring; inside the shape, and under Reduce Motion, there is no lean. `S`, `E` and `L` are fitted on Tasks 12 and 13's clean `material.drag.{out,up,far}` takes (`stretch` and `centre` of each take against the finger's distance outside the shape, signed by axis as ruling 3 reads them), over a grid with an edge guard as the law's (`problems()` names a lean on its grid edge).

- **Step 1 (not run): The fit's tests.** In `test_pressfit.py`: `test_the_lean_is_recovered_from_three_distances` (series built from known `S`, `E`, `L` at 40, 106 and 256 pt are fitted back within one grid step) and `test_problems_name_a_lean_on_its_grid_edge`. Run `cd packages/mobile && python3 -m unittest tool/glass_lab/harness/tests/test_pressfit.py`: FAIL (`AttributeError: module 'pressfit' has no attribute 'fit_lean'`).
- **Step 2 (not run): The fit.** `fit_lean`, the `lean` command (`pressfit.py lean <series...> --out <json> [--write]`, writing `ios27PressLeanShift`, `ios27PressLeanStretch` and `ios27PressLeanLength` into `ios27_press.dart` beside the table's other constants). Run the tests again: PASS; the harness gate.
- **Step 3 (not run): The package's tests.** In `glass_press_test.dart`: `a finger dragged outside the glass leans it toward the finger and back on release` (a 250 × 88 interactive glass; the pointer moves 100 pt past the right edge; after the growth settles `debugGlassPress` reports a centre shift and a ratio change of the fitted size, toward the finger; after the pointer lifts both return to zero), `a finger inside the glass does not lean it`, and `under Reduce Motion a finger outside the glass does not lean it`. Run `cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub test/motion/glass_press_test.dart`: FAIL.
- **Step 4 (not run): The lean.** Implement it; run the tests again: PASS; the package and example gates; `material.interactive`'s still check is unaffected (no lean without a drag).
- **Step 5 (not run): Fit and write.** `python3 tool/glass_lab/harness/pressfit.py lean $E/references.json $E/press-series.json --out $E/lean.json --write`; `grep PROBLEM` prints nothing; `lab.py build all`; the gates.
- **Step 6 (not run): Commit** (`feat(ios_liquid_glass): interactive glass leans toward a finger outside it`). Task 15 then judges `material.drag.{out,up,far}` on `stretch` and `centre` against new native recordings of the scenes the lean was fitted on: the results say so (the fit is not held out). About 3 h, of which none on the simulator.

### Task 15: Done runs, frame cost and the still check (spec §8, 2B.3)

**Files:**
- Create: `docs/liquid_glass/02b-motion/research/execution-2b3/done-*.txt`, `perf-*.json`, `still-*.txt`

- [ ] **Step 1: Reboot, check the press, record.** Both apps, every case, one command at a time (`run` re-records holed takes):

```bash
for s in material.interactive material.press.circle58 material.press.138x53 material.press.250x44 material.press.300x120 material.press.360x200 material.press.circle44 material.press.250x150 material.press.300x250 material.press.120x250 material.press.capsule36 material.drag.fast material.drag.out material.drag.far material.drag.up material.neighbours.0 material.neighbours.10 material.neighbours.40; do python3 tool/glass_lab/harness/lab.py run $s || { echo "STOP $s"; exit 1; }; done
for s in material.interactive material.drag.fast material.drag.out; do python3 tool/glass_lab/harness/lab.py run $s --a11y reduce-motion || { echo "STOP $s"; exit 1; }; done
python3 tool/glass_lab/harness/lab.py run material.morph --appearance dark --backdrop photo
```

then `lab.py report <run>` on each run (gotcha 26). About 75 cases in two apps, about 2 h with re-recordings.

- [ ] **Step 2: Count, and treat a missing case as failing.** Passing / judged / expected over `motion.*` per case (gates apart), every expected case listed:

```bash
python3 - build/glass_lab/runs/<each run of Step 1> <<'EOF' > $E/done-press.txt
import json, math, sys
from pathlib import Path
sys.path.insert(0, "tool/glass_lab/harness")
import manifest
scenes = {s.id: s for s in manifest.load()}
seen = set()
ok = lambda e: e[0] <= e[1] if e[2] == "max" else e[0] >= e[1]
for run in sys.argv[1:]:
    flags = json.loads((Path(run) / "run.json").read_text())
    suffix = "" if flags.get("a11y", "none") == "none" else "-" + flags["a11y"]
    for scene_dir in sorted(p for p in Path(run).iterdir() if p.is_dir() and p.name in scenes):
        scene = scenes[scene_dir.name]
        for case_dir in sorted(p for p in scene_dir.iterdir() if p.is_dir()):
            seen.add((scene.id, case_dir.name))
            path = case_dir / "result.json"
            if not path.exists():
                print(scene.id, case_dir.name, "MISSING: counted as failing")
                continue
            measures = json.loads(path.read_text())["measures"]
            judged = {k: v for k, v in measures.items() if k.startswith("motion.") and not k.startswith(("motion.events", "motion.touches", "motion.capture"))}
            gates = {k: v for k, v in measures.items() if k.startswith(("motion.events", "motion.touches", "motion.capture"))}
            if any(k.startswith("motion.capture") and not ok(v) for k, v in gates.items()):
                judged = {k: (math.inf, v[1], v[2]) if v[2] == "max" else (-math.inf, v[1], v[2]) for k, v in judged.items()}
            print(scene.id, case_dir.name, f"{sum(map(ok, judged.values()))}/{sum(math.isfinite(v[0]) for v in judged.values())}/{len(judged)}", "gates", f"{sum(map(ok, gates.values()))}/{len(gates)}", "failing", sorted(k for k, v in judged.items() if not ok(v)))
names = ("material.interactive", "material.press.circle58", "material.press.138x53", "material.press.250x44", "material.press.300x120", "material.press.360x200", "material.press.circle44", "material.press.250x150", "material.press.300x250", "material.press.120x250", "material.press.capsule36", "material.drag.fast", "material.drag.out", "material.drag.far", "material.drag.up", "material.neighbours.0", "material.neighbours.10", "material.neighbours.40")
expected = {(s, f"{a}-{b}") for s in names for a in scenes[s].appearances for b in scenes[s].backdrops}
expected |= {(s, f"{a}-{b}-reduce-motion") for s in ("material.interactive", "material.drag.fast", "material.drag.out") for a in scenes[s].appearances for b in scenes[s].backdrops}
for scene_id, case in sorted(expected - seen):
    print(scene_id, case, "MISSING: counted as failing")
EOF
```

A case whose `capture.<app>` gate fails (its kept take still holed after the retries) counts every motion measure as failing: the take check, not the rows, decides a holed step (ruling 16, T4). Every failing measure is looked at frame by frame before it is classed in Task 16. The morph run only reports whether `events.unpaired` changed now that the toggle presses (todo-2b2).

- [ ] **Step 3: Frame cost, with every take kept.** Nothing else runs on the Mac:

```bash
python3 - <<'EOF' > $E/perf-takes.json
import json, sys
sys.path.insert(0, "tool/glass_lab/harness")
import build, probe, sim
udid = sim.device()
bundle = build.FLUTTER_TARGETS["example"]
takes = [{"scene": scene, **probe.perf_take(udid, bundle, scene)} for scene in probe.perf_order(("perf.material", "perf.motion", "perf.slide"), 6)]
print(json.dumps(takes, indent=1))
EOF
```

A pair is two consecutive takes of `perf.material` and `perf.motion` (or `perf.slide`) in the alternating order; it is valid when both took frames for their whole window (`frames` > 0) and neither shows a stall the scene did not cause (a raster median over 2 × the scene's own median). Report each valid pair's ratio, the medians, the frame counts and p90s, and the dropped frames (the prototype's animated scenes produced 32 % and 44 % fewer frames, ruling 14); **at least two valid pairs per comparison**; within 20 % passes Done item 4.

- [ ] **Step 4: The A9 re-raster against `abe33abbc`.** In a scratch worktree of the execution worktree, never merged:

```bash
git -C /Users/omaraly/development/AI/Operator-2b3 worktree add --detach /Users/omaraly/development/AI/Operator-2b3-a9 abe33abbc
cp /Users/omaraly/development/AI/Operator-2b3/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/perf_scenes.dart /Users/omaraly/development/AI/Operator-2b3-a9/packages/mobile/packages/ios_liquid_glass/example/lib/lab/scenes/perf_scenes.dart
cd /Users/omaraly/development/AI/Operator-2b3-a9/packages/mobile && flutter pub get --offline && (cd packages/ios_liquid_glass/example && flutter analyze --no-pub)
```

If `perf_scenes.dart` does not analyze clean at `abe33abbc`, stop and report: do not edit it to fit (the review found it clean). Otherwise build the example in each tree with `lab.py build example` (each build installs its app over the other's) and take `perf.slide` alternately: HEAD, `abe33abbc`, `abe33abbc`, HEAD, HEAD, `abe33abbc`, rebuilding before each switch, with `probe.perf_take` as in Step 3; at least two valid pairs. Report the ratio. Remove the scratch worktree (`git -C /Users/omaraly/development/AI/Operator-2b3 worktree remove /Users/omaraly/development/AI/Operator-2b3-a9`) and rebuild this branch's example.

- [ ] **Step 5: Still glass no worse than 2A** (spec §8 item 7), a ratchet against 2B.2's final still runs, read in place from `/Users/omaraly/development/AI/glass-lab-runs/2b2/runs/` (`research/execution-2b2/final-checks/still-runs-index.txt`): `material.regular` (`20261008-230550`), `material.clear` (`-231709`), `material.tinted` (`-232144`), `material.edge` (`-232823`), `material.regular --a11y reduce-transparency` (`-233505`), `--a11y increase-contrast` (`-234625`), `tabbar.rest --flutter operator` (`-235737`), `button.press --flutter operator` (`20261009-000641`), `navbar.inline --flutter operator` (`20261008-225125`), **and `material.interactive` against the prototype's recording of `development` (`R/still-check-interactive.txt` names the run)**, which no archive holds (F14). Record each again with the same flags, `lab.py report` it, then `python3 tool/glass_lab/harness/still_check.py <reference run> build/glass_lab/runs/<new run>`. Expected: `missing: 0` and `worse: 0` in each: a press changes no still frame. A `worse` row stops the task: open the frames and report.

- [ ] **Step 6: Gates.** App, package, example, harness, all green; the counts in the report.

- [ ] **Step 7: Commit** the evidence.

### Task 16: `results-2b3.md`, `todo-2b3.md`, README and ROADMAP

**Files:**
- Create: `docs/liquid_glass/02b-motion/results-2b3.md`, `docs/liquid_glass/02b-motion/todo-2b3.md`
- Modify: `docs/liquid_glass/ROADMAP.md`, `packages/ios_liquid_glass/README.md` (if Task 15 changed what it says)

- [ ] **Step 1: `results-2b3.md`.** In 2B.2's form: the Done table (spec §8, 2B.3, items 1–8) with run folders; per case passing / judged / expected; every failing measure classed (a) the package moves differently, (b) the measure or model, (c) the mask or tracker, (d) a capture problem, with its evidence; the floors' sources (Task 13) beside the counts; which measures were also fitted by `pressfit` (the size law, the springs, the cut per size, the light per size) and that their passes are on new recordings of the same scenes; the held-out 44 × 44 circle's and 120 × 250 capsule's results, said to be held out, and the law's residual per fitted size; the perf pairs and dropped frames; the A9 ratio; the still check; the decisions (D1–D13) and the rulings that changed in execution. **Shown to the user before merge together with Task 10's block** (the user's condition on Operator's swap, D9).
- [ ] **Step 2: `todo-2b3.md`.** Everything still failing or deferred, by class, including the header's deferred carry-ins, D6's lean toward a far finger (with Task 14b's sketch) and D10's light colour.
- [ ] **Step 3: ROADMAP.** Status table and §6 (2B.3 done, with its counts), §7 rows "Interactive press (2.5)" and "Reduce Motion (7.3)", §8's numbers, §9's next step; gotchas 10 and 13 checked against `spike-interactive.md`; new gotchas: analysis on the Mac during a native take squeezes presses, the press take's capture holes and the rule that finds them (ruling 16), a source edited during a run makes the rest of the run refuse (Global Constraints), a pointer event has no frame time (ruling 12), a lone drag recognizer starts a scroll's drag activity at pointer down (ruling 11).
- [ ] **Step 4: Commit** (`docs(2b3): results, to-do and ROADMAP for 2B.3`).

## Self-review

- **Spec coverage.** L4: Task 1. N3, N4: Tasks 2, 12. N6 (press, `drag.fast` and `drag.out` under Reduce Motion): Tasks 12, 13, 15 (materialize, merge and morph N6 are 2B.1's and 2B.2's, carried with their failures, Done item 3). M7: Tasks 4, 5, 7, 14. M8: Tasks 5 (press under Reduce Motion), 6 (`LiquidStretch`), ruling 10 (`GlassGlow`). M9: Tasks 11, 16. M10: Tasks 8, 15. M11: Task 7. §8 items 1–8: Tasks 15 and 16. Operator press swap: Task 10 (D9, decided by the user, separable). The take rule and the floors: Tasks 1, 3, 13.
- **Departures from the spec**, each a ruling: no release when a drag leaves the glass, at any distance recorded (3); the lean toward a far finger not built, the user's decision D6 A (3, D6), a departure from spec (a2); no container-level glow layer (4); `GlassGlow` keeps its glow under Reduce Motion (10); the swell's follow spring not re-timed (13); a white light where native's changes colour on stripes (6, D10); the new scenes on `photo` only (19); the take rule's lost-frame test applied to native only where native always draws at 60 Hz (16).
- **Not built, with the user's decision pending:** D2, D4, D7, D8, D10 (recommendations given); D12 and D13 decided A by the user; D6 decided A by the user (Task 14b not to run); D1 settled by F20's test; D3 and D5 built; D9 decided by the user.
