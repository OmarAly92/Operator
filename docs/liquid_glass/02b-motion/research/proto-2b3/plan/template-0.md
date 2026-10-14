
## Tasks

Tasks 1–11 are the prototype's code, each split into a test patch and an implementation patch where it has tests, so every new test is seen to fail first (Task 9 adds tests that pass on arrival, by design); Task 10 is separable (D9). Tasks 12–16 are recordings, fits and verification that only execution can do (12 the native references, 13 the noise floors, 14 the refit, 15 the Done runs and frame cost, 16 the results and documents).

### Task 0: Setup

- [ ] **Step 1: Resolve the workspace offline.**

RUN[t00-setup]: `cd packages/mobile && flutter pub get --offline` => PASS

<<OUT t00-setup>>

