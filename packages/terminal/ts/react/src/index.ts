export { TerminalSurface, type TerminalSurfaceProps } from "./TerminalSurface.js";
export { AltScreenSlot, type AltScreenSlotProps } from "./AltScreenSlot.js";
export { createCompositionTarget, type CompositionTarget } from "@operator/terminal-core";
export {
	encodeMouseReport,
	type MouseModifiers,
	type MouseReportInput,
	type MouseReportKind,
} from "./mouse-report.js";
export { warpDarkTheme } from "@operator/terminal-renderer-dom";
export { createTerminalCore, type TerminalCoreOptions } from "@operator/terminal-core";
export { initTerminalCoreFromUrl } from "@operator/terminal-core/browser";
export type {
	FontConfig,
	HostCapabilities,
	TerminalCore,
	TerminalStrings,
	TerminalTheme,
} from "@operator/terminal-core";
