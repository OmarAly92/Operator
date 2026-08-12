// PostHog project the mobile app reports to.
//
// No key is baked in, so a build exports nothing unless EXPO_PUBLIC_POSTHOG_KEY
// supplies one. A PostHog project key is public (it ships in every client build
// by design) and not a secret, so a fork that wants mobile telemetry can either
// set the env var or hardcode its own key here, mirroring the desktop's shared
// constant.
export const MOBILE_POSTHOG_KEY = process.env.EXPO_PUBLIC_POSTHOG_KEY?.trim() || "";

export const MOBILE_POSTHOG_HOST =
	process.env.EXPO_PUBLIC_POSTHOG_HOST?.trim() || "https://us.i.posthog.com";

/**
 * Kill switches, mirroring the desktop's OPERATOR_TELEMETRY_DISABLED_EVENTS. Build-time
 * (EXPO_PUBLIC_* is inlined), so it controls the next build. A shipped binary
 * cannot be hotfixed from here; the runtime kill switch for an event already in
 * the field is the PostHog-side ingestion drop rule, the same lever used for the
 * legacy desktop events (see docs/posthog-cost-controls.md).
 */
export const MOBILE_TELEMETRY_DISABLED =
	(process.env.EXPO_PUBLIC_OPERATOR_TELEMETRY_DISABLED ?? "").trim() === "1";

export const MOBILE_DISABLED_EVENTS = (process.env.EXPO_PUBLIC_OPERATOR_TELEMETRY_DISABLED_EVENTS ?? "")
	.split(",")
	.map((name: string) => name.trim())
	.filter((name: string) => name.length > 0);
