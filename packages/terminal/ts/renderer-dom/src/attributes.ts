import {
	ATTR_BLINK,
	ATTR_CURLY_UNDERLINE,
	ATTR_DASHED_UNDERLINE,
	ATTR_DOTTED_UNDERLINE,
	ATTR_DOUBLE_UNDERLINE,
	ATTR_HIDDEN,
	ATTR_ITALIC,
	ATTR_OVERLINE,
	ATTR_STRIKE,
	ATTR_UNDERLINE,
	STYLE_DEFAULT_UNDERLINE,
} from "@operator/terminal-core";
import { styleCodeToCssVar } from "./style-code.js";

export const CLASS_BLINK = "terminal-blink";

export type UnderlineStyle = "single" | "double" | "curly" | "dotted" | "dashed";

export type Decorations = Readonly<{
	italic: boolean;
	hidden: boolean;
	blink: boolean;
	underline: UnderlineStyle | null;
	decor: string | null;
	underlineColour: string | null;
}>;

const UNDERLINES: readonly (readonly [number, UnderlineStyle])[] = [
	[ATTR_UNDERLINE, "single"],
	[ATTR_DOUBLE_UNDERLINE, "double"],
	[ATTR_CURLY_UNDERLINE, "curly"],
	[ATTR_DOTTED_UNDERLINE, "dotted"],
	[ATTR_DASHED_UNDERLINE, "dashed"],
];

export function decorationAttributes(attrs: number, underlineCode: number): Decorations {
	const underline = UNDERLINES.find(([bit]) => (attrs & bit) !== 0)?.[1] ?? null;
	const decor = `${underline ? "u" : ""}${attrs & ATTR_STRIKE ? "s" : ""}${attrs & ATTR_OVERLINE ? "o" : ""}`;
	return {
		italic: (attrs & ATTR_ITALIC) !== 0,
		hidden: (attrs & ATTR_HIDDEN) !== 0,
		blink: (attrs & ATTR_BLINK) !== 0,
		underline,
		decor: decor === "" ? null : decor,
		underlineColour: underlineCode === STYLE_DEFAULT_UNDERLINE ? null : styleCodeToCssVar(underlineCode),
	};
}

export function applyAttributes(run: HTMLElement, attrs: number, underlineCode: number): boolean {
	const decorations = decorationAttributes(attrs, underlineCode);
	if (decorations.italic) run.dataset.italic = "";
	if (decorations.hidden) run.dataset.hidden = "";
	if (decorations.blink) run.classList.add(CLASS_BLINK);
	if (decorations.underline) run.dataset.underline = decorations.underline;
	if (decorations.decor) run.dataset.decor = decorations.decor;
	if (decorations.underlineColour) run.style.setProperty("--terminal-underline", decorations.underlineColour);
	return decorations.underline !== null;
}

// xterm.js src/browser/renderer/dom/DomRendererRowFactory.ts:176-184
export function underlinedText(text: string): string {
	return text.replaceAll(" ", " ");
}
