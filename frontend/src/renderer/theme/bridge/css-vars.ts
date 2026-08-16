import type { AppSkin } from "../app-skin";
import { SKIN_TOKENS, type SlotName } from "../token-map.generated";

export function skinToCssVars(skin: AppSkin): Record<string, string> {
	const vars: Record<string, string> = {};
	for (const [slot, cssVar] of Object.entries(SKIN_TOKENS)) {
		vars[cssVar] = skin[slot as SlotName];
	}
	return vars;
}

export function applySkinVars(skin: AppSkin, root: HTMLElement = document.documentElement): void {
	for (const [cssVar, value] of Object.entries(skinToCssVars(skin))) {
		root.style.setProperty(cssVar, value);
	}
}
