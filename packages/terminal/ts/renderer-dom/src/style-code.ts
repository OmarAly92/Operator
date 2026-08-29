export const DEFAULT_FOREGROUND_CODE = 255;

export function styleCodeToCssVar(code: number): string {
	if (code >= 0 && code <= 15) {
		return `var(--terminal-ansi-${code})`;
	}
	if (code === DEFAULT_FOREGROUND_CODE) {
		return "var(--terminal-foreground)";
	}
	throw new Error(`unsupported style code ${code}`);
}
