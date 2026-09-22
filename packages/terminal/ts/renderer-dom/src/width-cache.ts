// xterm.js src/browser/renderer/dom/WidthCache.ts
export const REPEAT = 32;

export type Measurer = (text: string, bold: boolean, italic: boolean) => number;

export class WidthCache {
	private readonly cache = new Map<string, number>();

	constructor(private readonly measure: Measurer) {}

	get(text: string, bold: boolean, italic: boolean): number {
		const key = `${bold ? "b" : ""}${italic ? "i" : ""}:${text}`;
		let width = this.cache.get(key);
		if (width === undefined) {
			width = this.measure(text, bold, italic);
			this.cache.set(key, width);
		}
		return width;
	}

	clear(): void {
		this.cache.clear();
	}
}

export function createDomMeasurer(node: HTMLElement): Measurer {
	return (text, bold, italic) => {
		node.style.fontWeight = bold ? "700" : "";
		node.style.fontStyle = italic ? "italic" : "";
		node.textContent = text.repeat(REPEAT);
		const width = node.getBoundingClientRect().width / REPEAT;
		node.textContent = "M";
		node.style.fontWeight = "";
		node.style.fontStyle = "";
		return width;
	};
}
