export const COMPANY = {
  NAME: "Operator",
  SHORT_NAME: "Operator",
  MARKETING_URL: "https://operator.example.com",
  DOCS_URL: "https://operator.example.com/docs",
  GITHUB_URL: "https://github.com/OmarAly92/operator",
  GITHUB_REPO: "OmarAly92/operator",
  STATUS_URL: "https://status.operator.example.com",
  TRUST_URL: "https://operator.example.com/privacy/",
  MAIL_TO: "mailto:support@operator.example.com",
  X_URL: "https://github.com/OmarAly92/operator",
  LINKEDIN_URL: "https://github.com/OmarAly92/operator",
  DISCORD_URL: "https://github.com/OmarAly92/operator/discussions",
  FOUNDERS_EMAIL: "support@operator.example.com",
  REPORT_ISSUE_URL: "https://github.com/OmarAly92/operator/issues/new",
  LICENSE: "Apache-2.0",
  LICENSE_URL: "https://github.com/OmarAly92/operator/blob/main/LICENSE",
} as const;

export const THEME_STORAGE_KEY = "opr-theme";
export const POSTHOG_COOKIE_NAME = "ph_phc_";

export const OPEN_ROLES = [] as { title: string; url: string; location: string }[];

export const PLATFORMS = {
  MACOS: "macos",
  WINDOWS: "windows",
  LINUX: "linux",
} as const;

export const GITHUB_STARS_URL = "https://api.github.com/repos/OmarAly92/operator";

// macOS points at the .dmg: this is rollout step 6 of issue #3267, taken once the
// release conductor started publishing a signed, notarized dmg on the stable
// channel. Mounting it gives the drag-to-Applications window, so the app lands in
// /Applications instead of being unzipped into ~/Downloads and launched from
// there, which is what leaves macOS running it translocated or as a stale copy
// (#3617, #3527).
//
// The .zip keeps publishing forever regardless: MacUpdater can only install an
// update from a zip (findFile(files, "zip", ["pkg", "dmg"])), so the dmg is
// first-install only and never replaces it.
//
// These are static releases/latest/download links, so they 404 until a release
// actually carries the asset. Only the STABLE channel builds a dmg; if the links
// ever break, check that the newest non-prerelease release has both files rather
// than assuming the pipeline is broken. The download page itself is resilient
// here: it reads the live release list and falls back to the zip.
export const DOWNLOAD_URL_MAC_ARM64 = "https://github.com/OmarAly92/operator/releases/latest/download/operator-darwin-arm64.dmg";
export const DOWNLOAD_URL_MAC_X64 = "https://github.com/OmarAly92/operator/releases/latest/download/operator-darwin-x64.dmg";
export const DOWNLOAD_URL_WINDOWS = "https://github.com/OmarAly92/operator/releases/latest/download/operator-win32-x64.exe";
export const DOWNLOAD_URL_LINUX = "https://github.com/OmarAly92/operator/releases/latest/download/operator-linux-x64.AppImage";

// Operator Mobile. iOS ships as a TestFlight beta — the same link the desktop app's
// Connect Mobile panel opens (frontend/src/renderer/components/settings/
// ConnectMobileGetApp.tsx), so the two must be changed together.
export const TESTFLIGHT_URL = "https://testflight.apple.com/join/t4U3fu2H";

/** Apple's TestFlight app itself — step one, and useless to skip. */
export const TESTFLIGHT_APP_URL = "https://apps.apple.com/app/testflight/id899247664";

/** Public self-join Group that grants eligibility for the Android closed test. */
export const ANDROID_TESTER_GROUP_URL =
  "https://groups.google.com/g/opr-mobile-testers/about";

/** Google Play page where an eligible Group member opts in and installs. */
export const ANDROID_TEST_OPT_IN_URL =
  "https://play.google.com/apps/testing/operator.example.com";

export const AGENT_HARNESSES = 24;
export const TAGLINE = "Stop babysitting agents. Start merging real work.";
export const HERO_SUBHEADLINE = "Run a fleet of coding agents while keeping branches, reviews, and CI failures manageable.";
export const HERO_SECONDARY_SUBHEADLINE = "Isolated workspaces for Claude Code, Codex, and any CLI agent. Review every change from one dashboard. Free and open source.";

export const NAV_ITEMS = [
  { label: "Demo", href: "/#see-it" },
  { label: "Features", href: "/#features" },
  { label: "Changelog", href: "/changelog" },
  { label: "Docs", href: "/docs" },
] as const;
