import { act, cleanup } from "@testing-library/react";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { feed, font, loadWasm, renderSurface } from "./surface-harness";

describe("TerminalSurface mouse and wheel", () => {
	beforeAll(loadWasm);

	afterEach(() => {
		cleanup();
	});

	it("turns the wheel into arrow keys instead of scrolling nothing", () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => {
			feed(core, "\x1b[?1049h");
		});
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		surface.dispatchEvent(new WheelEvent("wheel", { deltaY: 120, bubbles: true, cancelable: true }));
		expect(onSendRaw).toHaveBeenCalled();
		expect(onSendRaw.mock.calls.at(-1)![0]).toMatch(/^(\x1bOB|\x1b\[B)+$/);
	});

	it("accumulates precise trackpad pixels using the measured cell height", () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => {
			feed(core, "\x1b[?1049h\x1b[?1h");
		});
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		surface.dispatchEvent(new WheelEvent("wheel", { deltaY: 8, bubbles: true, cancelable: true }));
		expect(onSendRaw).not.toHaveBeenCalled();
		surface.dispatchEvent(new WheelEvent("wheel", { deltaY: 9, bubbles: true, cancelable: true }));
		expect(onSendRaw).toHaveBeenCalledOnce();
		expect(onSendRaw).toHaveBeenCalledWith("\x1bOB");
	});

	it("accelerates a flick so it travels further than the same pixels crept", () => {
		const cellHeight = font.lineHeight * font.sizePx;
		let now = 1000;
		const clock = vi.spyOn(performance, "now").mockImplementation(() => now);
		const countRows = (onSendRaw: ReturnType<typeof vi.fn>) =>
			onSendRaw.mock.calls.reduce(
				(total, call) => total + ((call[0] as string).match(/\x1bOB|\x1b\[B/g)?.length ?? 0),
				0,
			);
		const drip = (events: number, deltaY: number, gapMs: number) => {
			cleanup();
			const onSendRaw = vi.fn();
			const { container, core } = renderSurface({ onSendRaw });
			act(() => {
				feed(core, "\x1b[?1049h\x1b[?1h");
			});
			const surface = container.querySelector(".terminal-host") as HTMLElement;
			for (let i = 0; i < events; i += 1) {
				now += gapMs;
				surface.dispatchEvent(new WheelEvent("wheel", { deltaY, bubbles: true, cancelable: true }));
			}
			return countRows(onSendRaw);
		};

		// Identical pixel travel -- 60px either way -- delivered at ~17px/s over
		// 3.6s versus ~375px/s over 160ms.
		const crept = drip(60, 1, 60);
		now += 1000;
		const flicked = drip(20, 3, 8);

		expect(crept).toBe(Math.trunc(60 / cellHeight));
		expect(flicked).toBeGreaterThan(crept * 2);
		clock.mockRestore();
	});

	it("treats line-mode wheel deltas as terminal lines", () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => {
			feed(core, "\x1b[?1049h\x1b[?1h");
		});
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		surface.dispatchEvent(new WheelEvent("wheel", {
			deltaY: 1,
			deltaMode: WheelEvent.DOM_DELTA_LINE,
			bubbles: true,
			cancelable: true,
		}));
		expect(onSendRaw).toHaveBeenCalledWith("\x1bOB");
	});

	it("sends sgr wheel reports when the program tracks the mouse", () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => {
			feed(core, "\x1b[?1049h\x1b[?1006h\x1b[?1000h\x1b[?1002h");
		});
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		surface.dispatchEvent(new WheelEvent("wheel", { deltaY: 120, bubbles: true, cancelable: true }));
		expect(onSendRaw).toHaveBeenCalled();
		expect(onSendRaw.mock.calls.at(-1)![0]).toMatch(/^(\x1b\[<65;\d+;\d+M)+$/);
	});

	it("reports wheel up with button 64", () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => {
			feed(core, "\x1b[?1049h\x1b[?1006h\x1b[?1002h");
		});
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		surface.dispatchEvent(new WheelEvent("wheel", { deltaY: -120, bubbles: true, cancelable: true }));
		expect(onSendRaw.mock.calls.at(-1)![0]).toMatch(/^(\x1b\[<64;\d+;\d+M)+$/);
	});

	it("falls back to arrow keys when only sgr mouse is enabled", () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => {
			feed(core, "\x1b[?1049h\x1b[?1006h");
		});
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		surface.dispatchEvent(new WheelEvent("wheel", { deltaY: 120, bubbles: true, cancelable: true }));
		expect(onSendRaw.mock.calls.at(-1)![0]).toMatch(/^(\x1bOB|\x1b\[B)+$/);
	});

	it("does not turn the wheel into keys outside the alternate screen", () => {
		const onSendRaw = vi.fn();
		const { container } = renderSurface({ onSendRaw });
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		surface.dispatchEvent(new WheelEvent("wheel", { deltaY: 120, bubbles: true, cancelable: true }));
		expect(onSendRaw).not.toHaveBeenCalled();
	});

	it("leaves a normal-buffer wheel to the block list when no program asked", () => {
		const onSendRaw = vi.fn();
		const { container } = renderSurface({ onSendRaw });
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		const event = new WheelEvent("wheel", { deltaY: 120, cancelable: true, bubbles: true });
		surface.dispatchEvent(event);
		expect(onSendRaw).not.toHaveBeenCalled();
		expect(event.defaultPrevented).toBe(false);
	});

	it("reports a normal-buffer wheel once the program asks for tracking", () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => {
			feed(core, "\x1b[?1006h\x1b[?1000h");
		});
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		const event = new WheelEvent("wheel", { deltaY: 120, cancelable: true, bubbles: true });
		surface.dispatchEvent(event);
		expect(onSendRaw).toHaveBeenCalledWith(expect.stringContaining("\x1b[<65;"));
		expect(event.defaultPrevented).toBe(true);
	});

	it("gives the block list a shift-wheel even when the program asked", () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => {
			feed(core, "\x1b[?1006h\x1b[?1000h");
		});
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		const event = new WheelEvent("wheel", {
			deltaY: 120,
			shiftKey: true,
			cancelable: true,
			bubbles: true,
		});
		surface.dispatchEvent(event);
		expect(onSendRaw).not.toHaveBeenCalled();
		expect(event.defaultPrevented).toBe(false);
	});

	it("reports a normal-buffer click once the program asks for tracking", () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => {
			feed(core, "\x1b[?1006h\x1b[?1000h");
		});
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		surface.dispatchEvent(new MouseEvent("mousedown", { button: 0, bubbles: true, cancelable: true }));
		surface.dispatchEvent(new MouseEvent("mouseup", { button: 0, bubbles: true, cancelable: true }));
		expect(onSendRaw.mock.calls.map((call) => call[0])).toEqual([
			expect.stringMatching(/^\x1b\[<0;\d+;\d+M$/),
			expect.stringMatching(/^\x1b\[<0;\d+;\d+m$/),
		]);
	});

	it("leaves a normal-buffer click alone when no program asked", () => {
		const onSendRaw = vi.fn();
		const { container } = renderSurface({ onSendRaw });
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		const event = new MouseEvent("mousedown", { button: 0, bubbles: true, cancelable: true });
		surface.dispatchEvent(event);
		expect(onSendRaw).not.toHaveBeenCalled();
		expect(event.defaultPrevented).toBe(false);
	});

	it("reports a drag under 1002 and never takes the default on motion", () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => {
			feed(core, "\x1b[?1006h\x1b[?1002h");
		});
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		surface.dispatchEvent(new MouseEvent("mousedown", { button: 0, bubbles: true, cancelable: true }));
		const move = new MouseEvent("mousemove", { bubbles: true, cancelable: true });
		surface.dispatchEvent(move);
		expect(onSendRaw.mock.calls.at(-1)![0]).toMatch(/^\x1b\[<32;\d+;\d+M$/);
		expect(move.defaultPrevented).toBe(false);
	});
});
