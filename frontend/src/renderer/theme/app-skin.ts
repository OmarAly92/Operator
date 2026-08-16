import { SKIN_TOKENS, type SlotName } from "./token-map.generated";

export type AppSkin = Record<SlotName, string>;

export type DerivedSlot = never;
export type RequiredSlot = Exclude<SlotName, DerivedSlot>;

export type SkinInput = Pick<AppSkin, RequiredSlot> & Partial<Pick<AppSkin, DerivedSlot>>;

export const DERIVED_DEFAULTS: Partial<Record<SlotName, (skin: Partial<AppSkin>) => string>> = {};

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
