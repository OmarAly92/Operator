import type { FontConfig } from "@operator/terminal-core";

export function defaultFont(): FontConfig {
	return {
		family: "ui-monospace, Menlo, Monaco, Consolas, monospace",
		sizePx: 14,
		lineHeight: 1.2,
		weight: 400,
		letterSpacingPx: 0,
		ligatures: false,
	};
}
