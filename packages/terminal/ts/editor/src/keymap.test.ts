import { describe, expect, it } from "vitest";
import { mapKey } from "./keymap";

const key = (init: Partial<KeyboardEvent> & { key: string }) =>
	({ ctrlKey: false, metaKey: false, altKey: false, shiftKey: false, ...init }) as KeyboardEvent;

describe("mapKey", () => {
	it("maps Enter to submit and Shift+Enter to a newline", () => {
		expect(mapKey(key({ key: "Enter" }))).toEqual({ kind: "submit" });
		expect(mapKey(key({ key: "Enter", shiftKey: true }))).toEqual({ kind: "newline" });
	});

	it("maps the readline motions users expect", () => {
		expect(mapKey(key({ key: "a", ctrlKey: true }))).toEqual({ kind: "home" });
		expect(mapKey(key({ key: "e", ctrlKey: true }))).toEqual({ kind: "accept-suggestion" });
		expect(mapKey(key({ key: "w", ctrlKey: true }))).toEqual({ kind: "delete-word-backward" });
		expect(mapKey(key({ key: "r", ctrlKey: true }))).toEqual({ kind: "reverse-search" });
	});

	// Warp binds cmd-backspace to kill_to_line_start and ctrl-u alongside it
	// (warp_tui/editor_interaction.rs); ctrl-u already killed the word here, so
	// it moves to the line to match, and cmd-delete kills forward.
	it("kills the line on Command+Backspace, and to the end on Command+Delete", () => {
		expect(mapKey(key({ key: "Backspace", metaKey: true }))).toEqual({
			kind: "delete-line-backward",
		});
		expect(mapKey(key({ key: "u", ctrlKey: true }))).toEqual({ kind: "delete-line-backward" });
		expect(mapKey(key({ key: "Delete", metaKey: true }))).toEqual({ kind: "delete-line-forward" });
		expect(mapKey(key({ key: "k", ctrlKey: true }))).toEqual({ kind: "delete-line-forward" });
	});

	it("leaves the word chords alone", () => {
		expect(mapKey(key({ key: "Backspace", altKey: true }))).toEqual({
			kind: "delete-word-backward",
		});
		expect(mapKey(key({ key: "w", ctrlKey: true }))).toEqual({ kind: "delete-word-backward" });
	});

	it("gives Tab to completions and ArrowRight to ghost-text acceptance", () => {
		expect(mapKey(key({ key: "Tab" }))).toEqual({ kind: "complete" });
		expect(mapKey(key({ key: "ArrowRight" }))).toEqual({ kind: "accept-suggestion" });
	});

	it("returns a passthrough for Ctrl-C so a running program still sees it", () => {
		expect(mapKey(key({ key: "c", ctrlKey: true }))).toEqual({
			kind: "passthrough",
			data: "\x03",
		});
	});

	it("passes through control chords without a local editing command", () => {
		expect(mapKey(key({ key: "l", ctrlKey: true }))).toEqual({
			kind: "passthrough",
			data: "\x0c",
		});
	});

	it("passes through Alt chords as terminal escape-prefixed input", () => {
		expect(mapKey(key({ key: "x", altKey: true }))).toEqual({
			kind: "passthrough",
			data: "\x1bx",
		});
	});

	it("returns null for a bare modifier so it is not treated as text", () => {
		expect(mapKey(key({ key: "Shift" }))).toBeNull();
	});
});
