# Task 20d: why material.edge's Flutter frames changed

## Verdict

2A is deterministic, and the change is real. It is not the Task 18 uniforms, a spring or scroll offset, or the drawn rect. 2B.1 changed when the pill's material is resolved. That changed which of two geometry paths the final frame ends on, and the two paths disagree by a fraction of a pixel when a glass sits at a fractional x. The fault is in the fork's geometry pipeline and predates 2A. 2A's exact rim came from the order things happened in. No 2A logic is broken.

## Evidence

1. **2A is deterministic.** The 2A-era runs of material.edge are 20260927-234202, 20260930-082046, 20261002-152214 and 20261002-202042. The last two are byte-identical in all 12 Flutter frames, five hours apart, with package commits in between. The two older runs differ everywhere, because they come from earlier material tables. 2b1-proto has no edge run.
2. **The pixels show a pure sub-pixel shift, not speckle.** In 2A vs new (automatic/dark-scroll ready), the signed difference along the pill's rim is `-+` on both the left and right edges. A least-squares shift of the rim profile gives these values:
   - Horizontal: left edge -0.245 px, right edge -0.235 px (light -0.248/-0.244, soft -0.249/-0.235, -0.244/-0.244).
   - Vertical: top and bottom 0.000 px.

   So the glass moved left by about 0.2 px. Its size is unchanged and its interior and label are identical. Left-edge profile, 2A vs new: `89.3 48.7 67.6 100.4` vs `82.9 43.6 73.8 104.1`.
3. **Device probe 1** (a throwaway `print` in `_buildGeometryImage` and `maybeRebuildGeometry`, with `render()` skipped; run 20261006-020852):
   - The pill geometry's top-left is at screen px (973.1640625, 181.0): fractional x, integer y.
   - With the geometry left as a Picture (`UnrenderedGeometryCache`), the ready and settled frames are **byte-identical to 2A** (n=0) and differ from the 20d run in the same 1334 px.
4. **Device probe 2** (committed behaviour plus stack traces; run 20261006-021029, byte-identical to the 20d run):
   - Frame 1: forced rebuild, then the final image is built from `UnrenderedGeometryCache`.
   - Then `GeometryTransformTrackingLayer.addToScene` (transform_tracking_repaint_boundary_mixin.dart:91) fires `onTransformChanged`. It always fires on a layer's first composite, because `_lastTransform` starts null. That sets `mightNeedUpdate`.
   - Frame 2: `maybeRebuildGeometry` takes the no-change branch and calls `geometry!.render()` (render_liquid_glass_geometry.dart:244). The final image is rebuilt from `RenderedGeometryCache`, which `_buildGeometryImage` draws with `canvas.drawImage(image, Offset.zero, Paint())` (liquid_glass_render_object.dart:394).
   - That image was rasterized on the pill's local pixel grid and is drawn at x = 973.164 px with nearest sampling. The rim snaps to the grid. The Picture path evaluates the SDF at the exact position.
5. **Why 2A ended on the Picture path.**
   - 2A's GlassEffect resolved its material at `fallbackSide` 88 on frame 1. It measured the side (44) in a post-frame `_SizeReporter` callback and called setState.
   - The dark 88 to 44 material change (thickness 7 to 10) passes `requiresGeometryRebuild`. So frame 2 did a **forced** rebuild after the first-composite transform event had been used up, and the frame stayed on the Picture.
   - 2B.1 resolves the side during layout on frame 1 (`RenderGlassMemberBox.performLayout` calls `sized`, then `material.resize(44, exact)`, glass_motion_coordinator.dart:284). Frame 1 already has the right geometry, so nothing forces a later rebuild, and the transform event moves the frame to the image path.
   - Side effect: 2B.1 drops 2A's one-frame flash of the 88 material.
6. **Why only material.edge changed.** Every other compared scene places its glass on whole points (`WholePointCenter`, fixed sizes). The two paths match there. The "Edit" pill's width comes from text, so its x is fractional. Any glass at a fractional x that relaid out or moved after its first frame showed the same rim snap in 2A.
7. **Candidates ruled out:**
   - (a) A widget test with fractional widths shows `GlassMember.resolve` equals `Offset.zero & size` to within 1 ulp, with no springs moving. The pill is not inside a scrollable.
   - (b) thickness equals effectiveThickness at visibility 1.
   - (d) The drawn rect equals the layout rect.
   - (c) is close in spirit: the cause is geometry-cache sequencing, not the null `_effective` check.

## Is it a regression?

It is not a 2B.1 logic regression. 2A was exact here only because a later forced rebuild happened to land after the transform event. The steady state of the fork is the snapped image path, and 2B.1 removed the later rebuild.

It is a real fault that predates 2A: glass at a fractional x shows its rim up to 0.5 px off its layout position once the geometry cache is rendered to an image. Measures do not change.

## Smallest fix, if one is wanted

Do not convert the cache to an image: in render_liquid_glass_geometry.dart:244, keep the geometry instead of `geometry = geometry!.render();`. This exact change is what probe 1 tested: material.edge then matches 2A byte for byte. Other scenes should be unchanged, because their glass sits on whole points, but they were not re-run.

Cost: the geometry shader runs again whenever the final geometry image is rebuilt, which happens only on geometry or link changes, not every frame. Perf was not measured.

The proper fix is larger: rasterize the matte on the screen pixel grid, or keep the fractional offset when drawing it.

The other choice is to accept the change and record that 2A's edge frames are not a valid baseline at the pill rim.

## Hygiene

- The throwaway edits were reverted with `git checkout -- packages/ios_liquid_glass/lib`.
- The temporary test file was deleted.
- The example was rebuilt from the committed tree.
- The probe runs are left under build/glass_lab/runs (20261006-020852 and 20261006-021029) as evidence.
