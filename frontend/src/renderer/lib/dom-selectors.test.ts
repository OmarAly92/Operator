import { createCompositionTarget } from "@operator/terminal-react";
import { afterEach, describe, expect, it } from "vitest";
import { activeTerminalInput, terminalHasFocus } from "./dom-selectors";

function mountSurface(options: { phase?: string; slot?: boolean; hiddenEditor?: boolean } = {}) {
	const container = document.createElement("div");
	if (options.phase) container.dataset.terminalActivationPhase = options.phase;
	if (options.slot) container.setAttribute("data-testid", "session-terminal-slot");
	const surface = document.createElement("div");
	surface.className = "terminal-surface";
	const host = document.createElement("div");
	host.className = "terminal-host";
	const editorHost = document.createElement("div");
	editorHost.className = "terminal-editor-host";
	if (options.hiddenEditor) editorHost.hidden = true;
	surface.append(host, editorHost);
	container.append(surface);
	document.body.append(container);
	return {
		container,
		host,
		editorHost,
		altInput: () => createCompositionTarget({ parent: host, onCommit: () => undefined }).element,
		editorInput: () =>
			createCompositionTarget({ parent: editorHost, onCommit: () => undefined }).element,
	};
}

describe("terminalHasFocus", () => {
	afterEach(() => {
		document.body.replaceChildren();
	});

	it("is true while the terminal's own composition input holds focus", () => {
		const surface = mountSurface({ phase: "visible" });
		const input = surface.editorInput();
		input.focus();
		expect(terminalHasFocus()).toBe(true);
	});

	it("is false for an input outside any terminal surface", () => {
		const outside = document.createElement("textarea");
		document.body.append(outside);
		outside.focus();
		expect(terminalHasFocus()).toBe(false);
	});
});

describe("activeTerminalInput", () => {
	afterEach(() => {
		document.body.replaceChildren();
	});

	it("finds the editor input of the visible terminal", () => {
		const surface = mountSurface({ phase: "visible" });
		const input = surface.editorInput();
		expect(activeTerminalInput()).toBe(input);
	});

	it("finds the alt-screen input and skips the hidden editor", () => {
		const surface = mountSurface({ phase: "visible", hiddenEditor: true });
		const alt = surface.altInput();
		surface.editorInput();
		expect(activeTerminalInput()).toBe(alt);
	});

	it("falls back to the session slot when no container is marked visible", () => {
		const surface = mountSurface({ slot: true });
		const input = surface.editorInput();
		expect(activeTerminalInput()).toBe(input);
	});

	it("returns null when no terminal is mounted", () => {
		expect(activeTerminalInput()).toBeNull();
	});
});
