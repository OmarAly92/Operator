import type { Theme, ThemeStyle } from "../../lib/theme";
import type { AppSkin } from "../app-skin";
import { catppuccinDark, catppuccinLight } from "./catppuccin";
import { darkSkin } from "./dark";
import { draculaDark, draculaLight } from "./dracula";
import { githubDark, githubLight } from "./github";
import { gruvboxDark, gruvboxLight } from "./gruvbox";
import { lightSkin } from "./light";
import { nordDark, nordLight } from "./nord";
import { rosePineDark, rosePineLight } from "./rose-pine";
import { solarizedDark, solarizedLight } from "./solarized";
import { tokyoNightDark, tokyoNightLight } from "./tokyo-night";

const REGISTRY: Partial<Record<ThemeStyle, { dark: AppSkin; light: AppSkin }>> = {
	github: { dark: githubDark, light: githubLight },
	catppuccin: { dark: catppuccinDark, light: catppuccinLight },
	dracula: { dark: draculaDark, light: draculaLight },
	"tokyo-night": { dark: tokyoNightDark, light: tokyoNightLight },
	"rose-pine": { dark: rosePineDark, light: rosePineLight },
	nord: { dark: nordDark, light: nordLight },
	gruvbox: { dark: gruvboxDark, light: gruvboxLight },
	solarized: { dark: solarizedDark, light: solarizedLight },
};

export function skinFor(style: ThemeStyle, theme: Theme): AppSkin {
	const pair = REGISTRY[style];
	if (pair) return theme === "light" ? pair.light : pair.dark;
	return theme === "light" ? lightSkin : darkSkin;
}
