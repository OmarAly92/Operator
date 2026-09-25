import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { defaultStrings, type OlderOutput } from "@operator/terminal-core";
import { LOAD_OLDER_RETRY_MS, mountLoadOlder, type LoadOlder } from "./load-older";

type Fake = { front: number; alt: boolean; canLoad: boolean; older: OlderOutput };

function harness(initial: Partial<Fake> = {}) {
	const state: Fake = { front: 0, alt: false, canLoad: true, older: { floor: null, marks: 0 }, ...initial };
	const container = document.createElement("div");
	document.body.append(container);
	const load = vi.fn<(before: number) => void>();
	const handle: LoadOlder = mountLoadOlder({
		container,
		source: {
			canLoad: () => state.canLoad,
			firstStableRow: () => state.front,
			altScreenActive: () => state.alt,
			olderOutput: () => state.older,
		},
		strings: { ...defaultStrings, loadOlderOutput: "Load older output" },
		load,
	});
	const button = () => container.querySelector<HTMLButtonElement>("[data-terminal-load-older]");
	return { state, container, load, handle, button };
}

describe("mountLoadOlder", () => {
	beforeEach(() => {
		vi.useFakeTimers();
	});

	afterEach(() => {
		vi.useRealTimers();
		document.body.replaceChildren();
	});

	it("shows nothing until the host has reported a floor", () => {
		const h = harness({ front: 500 });
		expect(h.button()).toBeNull();
		expect(h.handle.isButtonVisible()).toBe(false);
	});

	it("shows the button only while rows older than the pane exist", () => {
		const h = harness({ front: 500, older: { floor: 500, marks: 1 } });
		expect(h.button()).toBeNull();
		h.state.older = { floor: 200, marks: 2 };
		h.handle.update();
		expect(h.button()?.textContent).toBe("Load older output");
		expect(h.button()?.title).toBe("Load older output");
	});

	it("shows nothing when the host has no way to load", () => {
		const h = harness({ front: 500, canLoad: false, older: { floor: 0, marks: 1 } });
		expect(h.button()).toBeNull();
		h.state.canLoad = true;
		h.handle.update();
		expect(h.button()).not.toBeNull();
	});

	it("relabels the button when the host's strings change", () => {
		const h = harness({ front: 500, older: { floor: 0, marks: 1 } });
		h.handle.setStrings({ ...defaultStrings, loadOlderOutput: "Ältere Ausgabe laden" });
		expect(h.button()?.textContent).toBe("Ältere Ausgabe laden");
		expect(h.button()?.title).toBe("Ältere Ausgabe laden");
	});

	it("hides the button on the alternate screen", () => {
		const h = harness({ front: 500, older: { floor: 0, marks: 1 } });
		expect(h.button()).not.toBeNull();
		h.state.alt = true;
		h.handle.update();
		expect(h.button()).toBeNull();
	});

	it("asks for the rows above the pane's first row and waits for the answer", () => {
		const h = harness({ front: 500, older: { floor: 0, marks: 1 } });
		h.button()!.click();
		expect(h.load).toHaveBeenCalledWith(500);
		expect(h.button()).toBeNull();
		h.button()?.click();
		expect(h.load).toHaveBeenCalledTimes(1);
		h.state.front = 0;
		h.state.older = { floor: 0, marks: 2 };
		h.handle.update();
		expect(h.button()).toBeNull();
	});

	it("comes back when the answer leaves older rows still to load", () => {
		const h = harness({ front: 5000, older: { floor: 0, marks: 1 } });
		h.button()!.click();
		h.state.front = 2952;
		h.state.older = { floor: 0, marks: 2 };
		h.handle.update();
		expect(h.button()).not.toBeNull();
		h.button()!.click();
		expect(h.load).toHaveBeenLastCalledWith(2952);
	});

	it("disappears when the answer says nothing older is left", () => {
		const h = harness({ front: 500, older: { floor: 100, marks: 1 } });
		h.button()!.click();
		h.state.older = { floor: 500, marks: 2 };
		h.handle.update();
		expect(h.button()).toBeNull();
	});

	it("reappears once the pane's own cap trims the loaded rows again", () => {
		const h = harness({ front: 500, older: { floor: 0, marks: 1 } });
		h.button()!.click();
		h.state.front = 0;
		h.state.older = { floor: 0, marks: 2 };
		h.handle.update();
		expect(h.button()).toBeNull();
		h.state.front = 501;
		h.handle.update();
		expect(h.button()).not.toBeNull();
	});

	it("offers the button again when no answer arrives", () => {
		const h = harness({ front: 500, older: { floor: 0, marks: 1 } });
		h.button()!.click();
		expect(h.button()).toBeNull();
		vi.advanceTimersByTime(LOAD_OLDER_RETRY_MS);
		expect(h.button()).not.toBeNull();
	});

	it("removes the button, its listener and its timer on dispose", () => {
		const h = harness({ front: 500, older: { floor: 0, marks: 1 } });
		const button = h.button()!;
		const removeListener = vi.spyOn(button, "removeEventListener");
		button.click();
		expect(vi.getTimerCount()).toBe(1);
		h.handle.dispose();
		expect(vi.getTimerCount()).toBe(0);
		expect(removeListener).toHaveBeenCalledWith("click", expect.any(Function));
		expect(h.container.querySelector("[data-terminal-load-older]")).toBeNull();
		h.state.front = 900;
		h.handle.update();
		expect(h.container.querySelector("[data-terminal-load-older]")).toBeNull();
		button.click();
		expect(h.load).toHaveBeenCalledTimes(1);
	});
});
