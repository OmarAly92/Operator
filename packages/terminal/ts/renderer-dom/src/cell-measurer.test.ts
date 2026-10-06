import { afterEach, describe, expect, it, vi } from "vitest";
import { CellMeasurer } from "./cell-measurer";
import { ensureMeasureHost, HIDDEN_MEASURE_ID } from "./host-dom";
import { defaultFont } from "./default-font";

function stubFonts() {
	let finish: (ok: boolean) => void = () => undefined;
	const fonts = {
		load: vi.fn(
			() =>
				new Promise((resolve, reject) => {
					finish = (ok) => {
						if (ok) resolve([]);
						else reject(new Error("network"));
					};
				}),
		),
	};
	Object.defineProperty(document, "fonts", { value: fonts, configurable: true });
	return { fonts, finish: (ok: boolean) => finish(ok) };
}

function measureNodeWidths(...widths: number[]): void {
	const node = ensureMeasureHost().querySelector<HTMLElement>(`#${HIDDEN_MEASURE_ID}`)!;
	let call = 0;
	node.getBoundingClientRect = () => {
		const width = widths[Math.min(call, widths.length - 1)]!;
		call += 1;
		return { width, height: 16 } as DOMRect;
	};
}

const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("CellMeasurer", () => {
	afterEach(() => {
		delete (document as { fonts?: unknown }).fonts;
		document.getElementById("terminal-measure-host")?.remove();
	});

	it("measures again once the configured font finishes loading", async () => {
		const { fonts, finish } = stubFonts();
		measureNodeWidths(8.046875, 7.828125);
		const measurer = new CellMeasurer(() => measurer.invalidate());
		measurer.attach();

		expect(measurer.measure(defaultFont()).cellWidth).toBe(8.046875);
		expect(fonts.load).toHaveBeenCalledWith(`400 14px ${defaultFont().family}`);
		finish(true);
		await settle();

		expect(measurer.measure(defaultFont()).cellWidth).toBe(7.828125);
		expect(fonts.load).toHaveBeenCalledTimes(1);
	});

	it("keeps its measurement when the loaded font leaves the cell unchanged", async () => {
		const { finish } = stubFonts();
		measureNodeWidths(8);
		const onChange = vi.fn();
		const measurer = new CellMeasurer(onChange);
		measurer.attach();
		measurer.measure(defaultFont());

		finish(true);
		await settle();

		expect(onChange).not.toHaveBeenCalled();
	});

	it("keeps the fallback measurement when the font fails to load", async () => {
		const { fonts, finish } = stubFonts();
		measureNodeWidths(8, 7);
		const onChange = vi.fn();
		const measurer = new CellMeasurer(onChange);
		measurer.attach();
		measurer.measure(defaultFont());

		finish(false);
		await settle();
		measurer.invalidate();
		measurer.measure(defaultFont());

		expect(onChange).not.toHaveBeenCalled();
		expect(fonts.load).toHaveBeenCalledTimes(1);
	});

	it("does not report a font that loads after a reset", async () => {
		const { finish } = stubFonts();
		measureNodeWidths(8, 7);
		const onChange = vi.fn();
		const measurer = new CellMeasurer(onChange);
		measurer.attach();
		measurer.measure(defaultFont());

		measurer.reset();
		finish(true);
		await settle();

		expect(onChange).not.toHaveBeenCalled();
	});

	it("tells listeners when its metrics are invalidated", () => {
		const measurer = new CellMeasurer(() => undefined);
		const listener = vi.fn();
		const off = measurer.onChange(listener);

		measurer.invalidate();
		off();
		measurer.invalidate();

		expect(listener).toHaveBeenCalledTimes(1);
	});
});
