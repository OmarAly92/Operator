import type { TerminalTheme } from "@operator/terminal-core";
import { indexedRgb } from "./style-code.js";

export type Rgb = readonly [number, number, number];

// alacritty/src/display/content.rs:21-22
export const MIN_CURSOR_CONTRAST = 1.5;

const TAG_INDEXED = 0x0100_0000;
const TAG_RGB = 0x0200_0000;
const TAG_MASK = 0x0300_0000;
const COLOUR_MASK = 0x00ff_ffff;

export function parseHexColour(text: string): Rgb | null {
	const match = /^#([0-9a-f]{6})$/iu.exec(text.trim());
	if (!match) return null;
	const value = Number.parseInt(match[1]!, 16);
	return [(value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff];
}

// vte-0.15.0/src/ansi.rs:66-104 (Rgb::luminance, Rgb::contrast)
export function relativeLuminance([r, g, b]: Rgb): number {
	const channel = (value: number) => {
		const c = value / 255;
		return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
	};
	return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
}

export function contrastRatio(a: Rgb, b: Rgb): number {
	const la = relativeLuminance(a);
	const lb = relativeLuminance(b);
	const [darker, lighter] = la > lb ? [lb, la] : [la, lb];
	return (lighter + 0.05) / (darker + 0.05);
}

export function styleCodeToRgb(code: number, theme: TerminalTheme, role: "foreground" | "background"): Rgb | null {
	const tag = code & TAG_MASK;
	if (tag === TAG_RGB) return [(code >> 16) & 0xff, (code >> 8) & 0xff, code & 0xff];
	if (tag === TAG_INDEXED) {
		const index = code & 0xff;
		return index < 16 ? parseHexColour(theme.ansi[index]!) : indexedRgb(index);
	}
	const plain = code & COLOUR_MASK;
	if (plain <= 15) return parseHexColour(theme.ansi[plain]!);
	if (plain === 255) return parseHexColour(theme.foreground);
	if (plain === 254) return parseHexColour(role === "background" ? theme.background : theme.foreground);
	return null;
}

export function cursorLacksContrast(theme: TerminalTheme, backgroundCode: number): boolean {
	const cursor = parseHexColour(theme.cursor);
	const background = styleCodeToRgb(backgroundCode, theme, "background");
	if (!cursor || !background) return false;
	return contrastRatio(cursor, background) < MIN_CURSOR_CONTRAST;
}
