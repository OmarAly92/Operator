// @vitest-environment jsdom
import { beforeEach, describe, expect, it, vi } from "vitest";
import { createCompositionTarget } from "./composition-target.js";

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

	it("commits the composed text once, on compositionend", () => {
		const onCommit = vi.fn();
		const target = createCompositionTarget({ parent, onCommit });
		target.element.dispatchEvent(new CompositionEvent("compositionstart"));
		target.element.dispatchEvent(new CompositionEvent("compositionupdate", { data: "に" }));
		expect(onCommit).not.toHaveBeenCalled();
		target.element.dispatchEvent(new CompositionEvent("compositionend", { data: "日本" }));
		expect(onCommit).toHaveBeenCalledTimes(1);
		expect(onCommit).toHaveBeenCalledWith("日本");
	});

	it("clears the textarea after a commit so the next composition starts empty", () => {
		const target = createCompositionTarget({ parent, onCommit: () => undefined });
		target.element.value = "日本";
		target.element.dispatchEvent(new CompositionEvent("compositionend", { data: "日本" }));
		expect(target.element.value).toBe("");
	});

	it("does not commit an empty composition", () => {
		const onCommit = vi.fn();
		const target = createCompositionTarget({ parent, onCommit });
		target.element.dispatchEvent(new CompositionEvent("compositionend", { data: "" }));
		expect(onCommit).not.toHaveBeenCalled();
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
