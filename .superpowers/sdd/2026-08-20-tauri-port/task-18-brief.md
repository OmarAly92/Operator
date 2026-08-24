### Task 18: Build signed feeds and platform artifacts

**Files:**
- Create: `frontend/src-tauri/tauri.release.conf.json`
- Create: `frontend/scripts/tauri-feed.mjs`
- Create: `frontend/scripts/tauri-feed.test.mjs`
- Create: `frontend/scripts/package-tauri-mac-zip.sh`
- Create: `frontend/scripts/verify-tauri-artifacts.sh`
- Modify: `frontend/scripts/feed.mjs`
- Modify: `frontend/scripts/feed.test.mjs`
- Modify: `frontend/scripts/e2e-mac-update.mjs`
- Modify: `frontend/scripts/e2e-mac-update.test.mjs`
- Modify: `frontend/scripts/verify-mac-artifact.sh`
- Modify: `frontend/docs/desktop-release.md`
- Modify: `frontend/package.json`
- Modify: `.github/workflows/build-artifacts.yml`
- Modify: `.github/workflows/desktop-testing.yml`
- Modify: `.github/workflows/testing-build.yml`
- Modify: `.github/workflows/frontend-release.yml`
- Modify: `.github/workflows/feature-release.yml`
- Modify: `.github/workflows/mac-update-e2e.yml`
- Modify: `.github/workflows/release-latest-guard.yml`

**Interfaces:**
- Produces Tauri `latest.json`, `nightly.json`, and `pr<N>.json` feeds plus the stable/nightly/feature Electron-compatibility YAML feeds used by the installed fleet, including permanent `latest-mac.yml`.
- Produces macOS app/dmg/zip/updater archive, Windows NSIS/updater archive, and Linux AppImage/deb/rpm/updater artifacts while preserving `operator-darwin-{arm64,x64}.zip`, `operator-darwin-{arm64,x64}.dmg`, `operator-win32-x64.exe`, `operator-linux-x64.AppImage`, and deb/rpm aliases.
- Every base artifact includes daemon, agent-browser, ACP runtime, licenses, and required icons.

- [ ] **Step 1: Write failing feed tests**

Reject invalid semver, missing signature, wrong OS/architecture, cross-channel assets, insecure production URL, duplicate platform, absent required sidecar, a feature release that writes stable/nightly feeds, and any private-key material. Assert deterministic ordering, correct updater archive selection, compatibility YAML generation, permanent macOS zip/`latest-mac.yml`, and unchanged version-free aliases.

- [ ] **Step 2: Run the failure**

```bash
cd frontend
node --test scripts/tauri-feed.test.mjs
node --test scripts/feed.test.mjs scripts/e2e-mac-update.test.mjs
```

Expected: FAIL because the feed builder does not exist.

- [ ] **Step 3: Implement artifact construction and verification**

Archive the signed macOS app with `ditto -c -k --sequesterRsrc --keepParent`. Keep DMG and zip as release artifacts in addition to Tauri updater archives. Verify both with the existing mac script. Port every existing Electron/Forge release, testing-build, artifact, feature-channel, update-E2E, and latest-release guard workflow to the Tauri commands; do not leave parallel stale workflows. Inspect resources inside every platform package before generating feeds.

- [ ] **Step 4: Run real native update tests**

Test signed latest, nightly, feature-pin downgrade, return-home, and pin-clearing updates. On all three platforms, test both Tauri-to-Tauri updates and the Phase 0 Electron-to-Tauri migration or mandatory bridge-release path. Install NSIS on Windows, update a macOS app copy, and validate Linux package contents and signatures. A designated release conductor remains the only publisher.

- [ ] **Step 5: Verify and commit**

```bash
cd frontend
node --test scripts/tauri-feed.test.mjs
node --test scripts/feed.test.mjs scripts/e2e-mac-update.test.mjs
npm run verify:tauri-artifacts
git add src-tauri/tauri.release.conf.json scripts/tauri-* scripts/feed.mjs scripts/feed.test.mjs scripts/e2e-mac-update.mjs scripts/e2e-mac-update.test.mjs scripts/package-tauri-mac-zip.sh scripts/verify-tauri-artifacts.sh scripts/verify-mac-artifact.sh docs/desktop-release.md package.json ../.github/workflows/build-artifacts.yml ../.github/workflows/desktop-testing.yml ../.github/workflows/testing-build.yml ../.github/workflows/frontend-release.yml ../.github/workflows/feature-release.yml ../.github/workflows/mac-update-e2e.yml ../.github/workflows/release-latest-guard.yml
git commit -m "feat(release): build signed tauri artifacts and feeds"
```

