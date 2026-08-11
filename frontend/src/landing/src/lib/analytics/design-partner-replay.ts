/**
 * Session replay, scoped to the design-partner page and nothing else.
 *
 * The init config keeps `disable_session_recording: true` permanently, so replay
 * is never armed by configuration. Recording is started by an explicit call from
 * a component that only exists on this one route, which means the blast radius
 * is the route rather than the project.
 */

/**
 * The desktop app's PostHog project key, mirrored from shared/posthog-config.ts.
 *
 * Duplicated here deliberately: the shared source lives in the desktop package,
 * outside this static-export app. Arming replay on the desktop project would
 * start recording the screens of installs already in the field, so recording
 * refuses to start while the site's configured key is this one, and pointing the
 * site at its own project is what unlocks it.
 *
 * Empty while no desktop key is baked in, which makes the guard inert — an empty
 * site key is already refused as "no-key". The drift test forces this constant to
 * be reconciled if the desktop ever bakes a key again.
 *
 * A PostHog project key is public. It ships in every client bundle by design and
 * is not a credential.
 */
export const DESKTOP_PROJECT_KEY = "";

/** The only path permitted to record. */
export const REPLAY_PATH = "/design-partners";

export type ReplayDecision =
  | { record: true }
  | { record: false; reason: "no-key" | "shared-project" | "wrong-path" | "not-consented" };

/**
 * Decides whether this page load may record.
 *
 * Every condition must hold. Split out from the component so the refusals are
 * testable without a browser, because the interesting cases are the ones where
 * it must say no.
 */
export function replayDecision(input: {
  key: string | undefined;
  pathname: string;
  optedOut: boolean;
  desktopKey?: string;
}): ReplayDecision {
  const key = input.key?.trim() ?? "";
  const desktopKey = (input.desktopKey ?? DESKTOP_PROJECT_KEY).trim();
  if (!key) return { record: false, reason: "no-key" };
  if (desktopKey && key === desktopKey) return { record: false, reason: "shared-project" };

  const path = input.pathname.replace(/\/+$/, "") || "/";
  if (path !== REPLAY_PATH && !path.startsWith(`${REPLAY_PATH}/`)) {
    return { record: false, reason: "wrong-path" };
  }
  // Recording someone who declined analytics would be worse than not recording
  // at all, so consent is checked last and is not negotiable.
  if (input.optedOut) return { record: false, reason: "not-consented" };

  return { record: true };
}
