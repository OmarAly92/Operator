export const DEFAULT_FOREGROUND_CODE = 255;

const TAG_INDEXED = 0x0100_0000;
const TAG_RGB = 0x0200_0000;
const TAG_MASK = 0xff00_0000;

const CUBE_LEVELS = [0, 95, 135, 175, 215, 255];

export function styleCodeToCssVar(code: number): string {
	const tag = code & TAG_MASK;
	if (tag === TAG_RGB) {
		const red = (code >> 16) & 0xff;
		const green = (code >> 8) & 0xff;
		const blue = code & 0xff;
		return `rgb(${red} ${green} ${blue})`;
	}
	if (tag === TAG_INDEXED) {
		return indexedToCss(code & 0xff);
	}
	if (code >= 0 && code <= 15) {
		return `var(--terminal-ansi-${code})`;
	}
	if (code === DEFAULT_FOREGROUND_CODE) {
		return "var(--terminal-foreground)";
	}
	throw new Error(`unsupported style code ${code}`);
}

function indexedToCss(index: number): string {
	if (index < 16) {
		return `var(--terminal-ansi-${index})`;
	}
	if (index < 232) {
		const offset = index - 16;
		const red = CUBE_LEVELS[Math.floor(offset / 36) % 6]!;
		const green = CUBE_LEVELS[Math.floor(offset / 6) % 6]!;
		const blue = CUBE_LEVELS[offset % 6]!;
		return `rgb(${red} ${green} ${blue})`;
	}
	const level = 8 + (index - 232) * 10;
	return `rgb(${level} ${level} ${level})`;
}
