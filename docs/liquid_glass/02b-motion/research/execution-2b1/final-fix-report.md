# Final fix wave report

Changes
- Test: container removed while a ghost is in flight disposes cleanly (test/motion/glass_motion_coordinator_test.dart).
- Test: standalone ghost overlay entry removed once unused (count of _OverlayGhostLayer 1 while present, 0 after settle).
- Test + fix: GlassEffectContainer Stack gets alignment: Alignment.topLeft; builds with no Directionality.
- todo-2b1.md: five harness-fault rows (compare_topology, manifest topology measures, neck 0.0, table_source 1.0, events.pairs). File:lines verified at HEAD.
- ROADMAP.md and results-2b1.md: package count 122 -> 125, with the three added tests noted.

Fail-first
- Ghost dispose: removed `_ticker.dispose()` in GlassMotionCoordinator.dispose; test failed (exception). Restored.
- Overlay entry: removed `entry.remove()` in _removeIfIdle; test failed at `expect(layer, findsNothing)` (1 widget found). Restored.
- Directionality: before the fix the test threw "No Directionality widget found"; passes after.
- Note: the dispose-loop break used was the ticker dispose, not the ghost loop.

Gates
- app: analyze clean, +2146; package: analyze clean, +125; example: analyze clean, +13; harness: Ran 175 tests OK.
