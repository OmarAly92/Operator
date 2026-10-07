
## Tasks

Tasks 1–12 are the prototype's twelve code commits (Task 3 is not a patch: the executor makes its `noise.json` from its own takes), each split into a test patch and an implementation patch so every new test is seen to fail first; Tasks 13–24 are the fix round that followed the plan's independent review, whose findings are answered in the rulings (a refactor that changes no behaviour is one patch, a fix is a test patch then an implementation patch); Tasks 25–27 are recordings and verification that only execution can do (25 the noise floors, 26 the native reference for the spacing animation, 27 the verification runs and the results).

### Task 0: Setup

- [ ] **Step 1: Resolve the workspace offline.**

RUN[t00-setup]: `cd packages/mobile && flutter pub get --offline` => PASS

<<OUT t00-setup>>

