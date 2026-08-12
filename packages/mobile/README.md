# operator_mobile

A Flutter thin client for the Operator daemon. It talks to a paired daemon over
HTTP/SSE the same way the desktop renderer does, rather than embedding any
orchestration logic of its own.

This package is the in-progress Flutter port of the mobile app. The previous
React Native implementation is frozen at `packages/mobile_rn` and stays on
disk, untouched, as the reference the port is built from until milestone M6,
when the RN tree is deleted and this package becomes the only mobile client.
`packages/mobile_rn`'s CI workflow is disabled so the frozen tree cannot fail
CI.

As of M0 this package ships `lib/core` only — data layer, error handling, the
Operator skin/theme, a small set of core widgets, and DI/routing/bootstrap.
No features live under `lib/` yet; those land starting with M1.

## Running the gate

```bash
cd packages/mobile
flutter analyze
flutter test
```

Both must be clean/green before any change is considered done. The app is
not run or built as part of this implementation phase — verification is
`flutter analyze` and `flutter test` only.
