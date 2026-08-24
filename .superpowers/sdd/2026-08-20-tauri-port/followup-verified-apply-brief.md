# Follow-up task (spawned by Task 18): project-owned verified APPLY path

## Why spawned rather than delivered in Task 18

Task 17 recorded the apply stop against the pinned plugin's own source
(tauri-plugin-updater 2.10.1 `install_inner` writes installer/recovery files to
OS-default temp/cache dirs that no API can redirect — violating the state-root
boundary rule). Delivering the replacement in Task 18 would mean writing a
per-platform bundle swapper that cannot be honestly verified in this task:
Windows NSIS handoff and Linux AppImage replacement are only testable on their
native runners, and macOS bundle replacement interacts directly with signing,
notarization and quarantine. A half-tested installer writer is a worse release
risk than the current fail-closed stop, which leaves staged builds verified on
disk and surfaces a clear error from updates_install.

## Scope

Per platform, inside `<state-root>/updater/staged/<version>/`:

1. **macOS**: extract the staged `.app.tar.gz` (tar, matching the plugin) into
   updater tmp; verify codesign seal + (when signed) staple of the EXTRACTED
   bundle BEFORE touching the installed one; swap via same-volume rename with a
   backup dir for recovery-on-next-launch; relaunch.
2. **Windows**: run the staged NSIS installer silently (`/S`) after verifying
   its Authenticode status when signed; handle the WebView2 bootstrapper path;
   exit-with-relaunch semantics identical to Electron's quitAndInstall.
3. **Linux AppImage**: replace the running AppImage via same-device rename when
   possible (documented fallback beside the AppImage per Task 17's residual
   note (a)); deb/rpm installs stay manual (system-package-managed).
4. Wire `updates_install` to this path, removing
   `APPLY_DEFERRED_MESSAGE`; flip `mac-update-e2e.yml` default mode to
   full-install; extend the E2E harness tests.
5. Evidence: native-runner E2E transcripts for latest, nightly,
   feature-pin-downgrade, return-home, pin-clearing on all three platforms.
6. Electron-to-Tauri migration coverage rides on this path landing: the
   ported `mac-update-e2e.yml` full-install mode already asserts the
   migration update once apply exists — no separate Phase-0 surface needed.

Owner: a dedicated follow-up dispatch (fresh implementer + full review loop),
scheduled after Tasks 19–22 and REQUIRED before any release ships (carries
Task 17's release-gating deferral #3).
