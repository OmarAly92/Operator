# 2A.2: improvements still to do on the static look

Date: 2026-10-02. Status: **TODO, not planned yet.** These are the residuals left after 2A, 2A.1 and the 2A.1 review fix wave (branch `feat/ios-liquid-glass-2a`, merged into `development`).

Where 2A ended: Done item 3 passes 10 of 20, item 4 5 of 6, item 5 17 of 20, item 6 22 of 32 measures, and item 8 (frame cost) passes. Every number and its run folder is in `results-2a1.md`. ROADMAP §6 classes each open item by cause.

When this becomes a project, it follows ROADMAP §5:
1. prototype every item on the iOS 27 simulator;
2. write a plan with the tested code embedded;
3. a fresh local session executes it;
4. review here.

It must never loosen a threshold or a measure.

## Needs shader work (the 2A.2 round)

| Item | Evidence | What native does | Likely fix |
|---|---|---|---|
| Tinted glass rings: fails all 6 `material.tinted` cases on rim (dark-black 24.35, light-black 14.34, others 9–11) | run `20261002-151504`; audit in `results-2a1.md` | A 2 px dark ring just **inside** the prominent button's edge, and a **tint-coloured** outline ring just outside the tinted block. Ours draws a black-only outline outside the shape. | An outline colour taken from the tint, plus an inner ring term for tinted glass; tune both on `material.tinted` with the `block` and `run` regions. |
| Fine detail inside the smallest glass: `material.regular` dark-text fails rim 10.18, worst side the 44 pt pill's right end at 16.89 | run `20261002-145817` | Small glass keeps sharp text detail visible inside it near the edge. Ours frosts it away. | A sharp-detail (less frosted) term near the edge of small glass, or size-dependent frost in the edge band. |
| Clear glass edge band over the photo: `material.clear` dark-photo and light-photo rim 10.92 | runs `20261002-151004`, fix wave `201611` | Native clear glass keeps the photo's content crisp up to the edge. Ours blurs it at the edge band. | Less frost and dispersion in the clear rows' edge band, or a clear-specific edge term. 190 earlier clear candidates never got the photo rim below 10.80, so this needs a model change, not a retune. |
| Our outline wraps further round the curved ends than native's | seen side by side in passing cases; not measured yet | Native's outline fades out earlier around the capsule's ends. | First add a measure for it (the four-sided rim samples only the middle of each side), then narrow the outline's angular spread. |
| Native's continuous corners: its capsule's flat top starts about 19 pt later at 200 pt (x 139.7 pt against our 112) | plan-2a1 ruling 17 | A continuous-curvature capsule, like SwiftUI's default glass shape. | A continuous-corner capsule shape in the renderer's SDF, used by `GlassShape.capsule()`. |

## Measurement noise (fix the measure, not the glass)

- **"Box 2 pt" on light photo**, in plain, Reduce Transparency and Increase Contrast: a detector flip. The frames differ by at most 2 levels per channel (0.10–0.14 mean luma), and Flutter's maximum-channel difference from bare sits at 6.67–7.00 against the detector's threshold of 6. Fix: make the box detector robust near its threshold (hysteresis or a luma-based threshold), and prove that no real placement error is hidden.
- **Reduce Transparency light-text rim 7.90:** one sample out of 288; without it the case reads 4.35. Fix: a robust rim statistic, such as a trimmed RMS or one outlier allowed per side, with a test that a real rim difference still fails.

## Lab scene (fix the scene, not the package)

- The example's "Run" button uses a Material `play_arrow` icon about 10 pt tall; native's SF Symbol `play.fill` is about 13.67 pt. The Run sample lines also cross Flutter's label. Fix: size the icon to native's glyph box, and keep the rim sample lines off the label, or measure the button without its label.

## Spec decision needed

- The soft scroll edge in light mode stays at MAD 4.07 against 4.00. The tuner keeps the lowest overall score, so it will not trade a slightly worse score for passing this one measure (narrowed pass `tune/20261002-195020` wrote nothing). Decide whether to:
  - add a "pass the threshold first" objective to `tune`;
  - accept 4.07 as within noise; or
  - improve the soft renderer.

## Belongs to projects 3 and 4 (Operator components, not the material)

- Operator's nav bar trailing group fuses into a figure-8 where native draws one capsule (`navbar.inline`). This is grouped bar items, project 3.
- Operator's icons and labels on glass take Operator's green accent where native stays white or black (`navbar.inline`, `button.press`). This is component colours, projects 3 and 4.
- `navbar.inline` dark-stripes rim 16.70 is worse than the project 1 baseline (16.37) and 2A (15.48). Re-check it when the nav bar is rebuilt in project 3.
- 10 of 32 Operator measures did not halve (`results-2a1.md`, item 6).

## Smaller deferred items (ROADMAP §6)

- Shader findings B2 and B3 from the 2A.1 code review:
  - the outer half of the edge pixel samples the backdrop further in than its neighbours;
  - edge precision depends on lens thickness.
- Edge light is coupled to lens thickness, which is a design question.
- The scroll edge's first frame shows no blur until its shader loads.
- The `tune` freshness guard has known gaps.
- The lab driver crashed three times on the photo backdrop with an empty log; the same command passed when retried.
