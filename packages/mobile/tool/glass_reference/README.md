# Glass reference

A native SwiftUI app that renders the glass lab scene with Apple's real Liquid Glass.
It is the ground truth the Flutter glass engine is tuned against.

- `./run.sh rest` or `./run.sh sheet` builds it with `swiftc`, installs it on the
  iPhone 17 Pro iOS 26 simulator and launches it.
- `./run_lab.sh rest` does the same for the Flutter app's glass lab route (Task 2).
- `./capture.sh` screenshots both in light and dark for both scenes and writes
  `build/captures/compare_*.png`, plus `_zoom` crops of the top and bottom chrome.

The scene geometry is fixed in points and must stay identical in `GlassReference.swift`
and `lib/core/widgets/glass/lab/glass_lab_backdrop.dart`.
