import type { Theme, ThemeStyle } from "../../lib/theme";
import type { AppSkin } from "../app-skin";
import { darkSkin } from "./dark";
import { lightSkin } from "./light";

const REGISTRY: Partial<Record<ThemeStyle, { dark: AppSkin; light: AppSkin }>> = {};

export function skinFor(style: ThemeStyle, theme: Theme): AppSkin {
	const pair = REGISTRY[style];
	if (pair) return theme === "light" ? pair.light : pair.dark;
	return theme === "light" ? lightSkin : darkSkin;
}
