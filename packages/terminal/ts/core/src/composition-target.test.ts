// @vitest-environment jsdom
import { beforeEach, describe, expect, it, vi } from "vitest";
import { anchorFromElement, createCompositionTarget } from "./composition-target.js";

describe("createCompositionTarget", () => {
	let parent: HTMLElement;

	beforeEach(() => {
		parent = document.createElement("div");
		document.body.append(parent);
	});

	it("mounts a focusable textarea that is visually hidden", () => {
		const target = createCompositionTarget({ parent, onCommit: () => undefined });
		expect(target.element.tagName).toBe("TEXTAREA");
		expect(parent.contains(target.element)).toBe(true);
		expect(target.element.getAttribute("aria-hidden")).toBe("true");
		target.dispose();
		expect(parent.contains(target.element)).toBe(false);
	});

	it("reports composing between compositionstart and compositionend", () => {
		const target = createCompositionTarget({ parent, onCommit: () => undefined });
		expect(target.isComposing()).toBe(false);
		target.element.dispatchEvent(new CompositionEvent("compositionstart"));
		expect(target.isComposing()).toBe(true);
		target.element.dispatchEvent(new CompositionEvent("compositionend", { data: "日" }));
		expect(target.isComposing()).toBe(false);
	});

	it("commits the textarea's settled value once, a tick after compositionend", () => {
		vi.useFakeTimers();
		const onCommit = vi.fn();
		const target = createCompositionTarget({ parent, onCommit });
		target.element.dispatchEvent(new CompositionEvent("compositionstart"));
		target.element.value = "に";
		target.element.dispatchEvent(new CompositionEvent("compositionupdate", { data: "に" }));
		target.element.value = "日";
		target.element.dispatchEvent(new CompositionEvent("compositionend", { data: "日" }));
		expect(onCommit).not.toHaveBeenCalled();
		target.element.value = "日本";
		vi.runAllTimers();
		expect(onCommit).toHaveBeenCalledTimes(1);
		expect(onCommit).toHaveBeenCalledWith("日本");
		expect(target.element.value).toBe("");
		expect(target.isComposing()).toBe(false);
		vi.useRealTimers();
	});

	it("sends only the finished part when a new composition starts before the tick", () => {
		vi.useFakeTimers();
		const onCommit = vi.fn();
		const target = createCompositionTarget({ parent, onCommit });
		target.element.dispatchEvent(new CompositionEvent("compositionstart"));
		target.element.value = "日";
		target.element.dispatchEvent(new CompositionEvent("compositionend", { data: "日" }));
		target.element.dispatchEvent(new CompositionEvent("compositionstart"));
		target.element.value = "日ほ";
		vi.runAllTimers();
		expect(onCommit).toHaveBeenCalledTimes(1);
		expect(onCommit).toHaveBeenCalledWith("日");
		expect(target.isComposing()).toBe(true);
		expect(target.element.value).toBe("日ほ");
		vi.useRealTimers();
	});

	it("does not commit an empty composition", () => {
		vi.useFakeTimers();
		const onCommit = vi.fn();
		const target = createCompositionTarget({ parent, onCommit });
		target.element.dispatchEvent(new CompositionEvent("compositionstart"));
		target.element.dispatchEvent(new CompositionEvent("compositionend", { data: "" }));
		vi.runAllTimers();
		expect(onCommit).not.toHaveBeenCalled();
		vi.useRealTimers();
	});

	it("shows the in-progress text at the anchor and hides it when composition ends", () => {
		vi.useFakeTimers();
		const target = createCompositionTarget({ parent, onCommit: () => undefined, anchor: () => ({ left: 24, top: 40, height: 20 }) });
		expect(parent.contains(target.view)).toBe(true);
		expect(target.view.classList.contains("active")).toBe(false);
		target.element.dispatchEvent(new CompositionEvent("compositionstart"));
		target.element.value = "に";
		target.element.dispatchEvent(new CompositionEvent("compositionupdate", { data: "に" }));
		expect(target.view.classList.contains("active")).toBe(true);
		expect(target.view.textContent).toBe("‎に‎");
		expect(target.view.style.left).toBe("24px");
		expect(target.view.style.top).toBe("40px");
		expect(target.view.style.height).toBe("20px");
		target.element.dispatchEvent(new CompositionEvent("compositionend", { data: "に" }));
		expect(target.view.classList.contains("active")).toBe(false);
		vi.runAllTimers();
		vi.useRealTimers();
	});

	it("anchorFromElement measures the cell against the parent's padding box", () => {
		const cell = document.createElement("span");
		parent.append(cell);
		vi.spyOn(parent, "getBoundingClientRect").mockReturnValue({ left: 100, top: 50 } as DOMRect);
		vi.spyOn(cell, "getBoundingClientRect").mockReturnValue({ left: 132, top: 90, height: 20 } as DOMRect);
		Object.defineProperty(parent, "clientLeft", { value: 1 });
		Object.defineProperty(parent, "clientTop", { value: 1 });
		Object.defineProperty(parent, "scrollTop", { value: 10, writable: true });
		expect(anchorFromElement(parent, cell)).toEqual({ left: 31, top: 49, height: 20 });
		expect(anchorFromElement(parent, null)).toBeNull();
	});

	it("commits an in-flight composition when focus is lost", () => {
		const onCommit = vi.fn();
		const target = createCompositionTarget({ parent, onCommit });
		target.element.dispatchEvent(new CompositionEvent("compositionstart"));
		target.element.value = "にほ";
		target.element.dispatchEvent(new FocusEvent("blur"));
		expect(onCommit).toHaveBeenCalledExactlyOnceWith("にほ");
		expect(target.isComposing()).toBe(false);
	});

	it("does not commit on blur when nothing is composing", () => {
		const onCommit = vi.fn();
		const target = createCompositionTarget({ parent, onCommit });
		target.element.dispatchEvent(new FocusEvent("blur"));
		expect(onCommit).not.toHaveBeenCalled();
	});
});
