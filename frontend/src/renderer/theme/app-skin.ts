import { SKIN_TOKENS, type SlotName } from "./token-map.generated";

export type AppSkin = Record<SlotName, string>;

export type DerivedSlot =
	| "statusTerminated"
	| "sidebarBorder"
	| "bgPrimary"
	| "bgSecondary"
	| "bgTertiary"
	| "bgElevated"
	| "bgSidebar"
	| "textPrimary"
	| "textMuted"
	| "textPassive"
	| "colorBorder"
	| "borderStrong"
	| "colorAccent"
	| "colorAccentForeground"
	| "dangerStrong"
	| "statusIdle"
	| "statusExited"
	| "warning"
	| "success"
	| "danger";
export type RequiredSlot = Exclude<SlotName, DerivedSlot>;

export type SkinInput = Pick<AppSkin, RequiredSlot> & Partial<Pick<AppSkin, DerivedSlot>>;

export const DERIVED_DEFAULTS: Partial<Record<SlotName, (skin: Partial<AppSkin>) => string>> = {
	statusTerminated: (skin) => skin.chart3!,
	sidebarBorder: (skin) => skin.border!,
	bgPrimary: (skin) => skin.background!,
	bgSecondary: (skin) => skin.card!,
	bgTertiary: (skin) => skin.muted!,
	bgElevated: (skin) => skin.popover!,
	bgSidebar: (skin) => skin.sidebar!,
	textPrimary: (skin) => skin.foreground!,
	textMuted: (skin) => skin.mutedForeground!,
	textPassive: (skin) => skin.chart3!,
	colorBorder: (skin) => skin.border!,
	borderStrong: (skin) => skin.input!,
	colorAccent: (skin) => skin.primary!,
	colorAccentForeground: (skin) => skin.primaryForeground!,
	dangerStrong: (skin) => skin.destructive!,
	statusIdle: (skin) => skin.mutedForeground!,
	statusExited: (skin) => skin.destructive!,
	warning: (skin) => skin.statusNeedsYou!,
	success: (skin) => skin.statusReady!,
	danger: (skin) => skin.destructive!,
};

export function defineSkin(input: SkinInput): AppSkin {
	const resolved = { ...input } as AppSkin;
	for (const slot of Object.keys(SKIN_TOKENS) as SlotName[]) {
		if (resolved[slot] !== undefined) continue;
		const derive = DERIVED_DEFAULTS[slot];
		if (!derive) throw new Error(`skin is missing required slot: ${slot}`);
		resolved[slot] = derive(resolved);
	}
	return resolved;
}
