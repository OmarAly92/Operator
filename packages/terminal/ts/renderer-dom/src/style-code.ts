export const DEFAULT_FOREGROUND_CODE = 255;

const TAG_INDEXED = 0x0100_0000;
const TAG_RGB = 0x0200_0000;
const TAG_MASK = 0x0300_0000;
const FLAG_BOLD = 0x0400_0000;
const FLAG_DIM = 0x0800_0000;
const COLOUR_MASK = 0x00ff_ffff;

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
	const plain = code & COLOUR_MASK;
	if (plain >= 0 && plain <= 15) {
		return `var(--terminal-ansi-${plain})`;
	}
	if (plain === DEFAULT_FOREGROUND_CODE) {
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

export function styleCodeIsBold(code: number): boolean {
	return (code & FLAG_BOLD) !== 0;
}

export function styleCodeIsDim(code: number): boolean {
	return (code & FLAG_DIM) !== 0;
}
