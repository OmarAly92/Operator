import { describe, expect, it } from "vitest";
import { encodeKey } from "./encode-key";

const key = (init: Partial<KeyboardEvent> & { key: string }) =>
	({ ctrlKey: false, metaKey: false, altKey: false, shiftKey: false, ...init }) as KeyboardEvent;

describe("encodeKey", () => {
	it("distinguishes Tab from Shift+Tab", () => {
		expect(encodeKey(key({ key: "Tab" }))).toBe("\t");
		expect(encodeKey(key({ key: "Tab", shiftKey: true }))).toBe("\x1b[Z");
	});

	it("encodes Escape", () => {
		expect(encodeKey(key({ key: "Escape" }))).toBe("\x1b");
	});

	it("switches the arrows between normal and application cursor mode", () => {
		expect(encodeKey(key({ key: "ArrowUp" }))).toBe("\x1b[A");
		expect(encodeKey(key({ key: "ArrowUp" }), true)).toBe("\x1bOA");
		expect(encodeKey(key({ key: "ArrowLeft" }), true)).toBe("\x1bOD");
	});

	it("parameterises a modified arrow instead of dropping the modifier", () => {
		expect(encodeKey(key({ key: "ArrowRight", shiftKey: true }))).toBe("\x1b[1;2C");
		expect(encodeKey(key({ key: "ArrowRight", ctrlKey: true }))).toBe("\x1b[1;5C");
		expect(encodeKey(key({ key: "ArrowRight", ctrlKey: true, shiftKey: true }))).toBe("\x1b[1;6C");
	});

	it("encodes the navigation and function keys", () => {
		expect(encodeKey(key({ key: "PageUp" }))).toBe("\x1b[5~");
		expect(encodeKey(key({ key: "PageDown" }))).toBe("\x1b[6~");
		expect(encodeKey(key({ key: "Insert" }))).toBe("\x1b[2~");
		expect(encodeKey(key({ key: "Delete" }))).toBe("\x1b[3~");
		expect(encodeKey(key({ key: "F1" }))).toBe("\x1bOP");
		expect(encodeKey(key({ key: "F12" }))).toBe("\x1b[24~");
	});

	it("encodes control chords as control codes", () => {
		expect(encodeKey(key({ key: "c", ctrlKey: true }))).toBe("\x03");
		expect(encodeKey(key({ key: "e", ctrlKey: true }))).toBe("\x05");
		expect(encodeKey(key({ key: "r", ctrlKey: true }))).toBe("\x12");
		expect(encodeKey(key({ key: " ", ctrlKey: true }))).toBe("\x00");
	});

	it("keeps Option+Left/Right as word motion the way macOS terminals do", () => {
		expect(encodeKey(key({ key: "ArrowLeft", altKey: true }))).toBe("\x1bb");
		expect(encodeKey(key({ key: "ArrowRight", altKey: true }))).toBe("\x1bf");
		expect(encodeKey(key({ key: "ArrowLeft", altKey: true, shiftKey: true }))).toBe("\x1b[1;4D");
	});

	it("prefixes an Alt chord with Escape", () => {
		expect(encodeKey(key({ key: "b", altKey: true }))).toBe("\x1bb");
		expect(encodeKey(key({ key: "Backspace", altKey: true }))).toBe("\x1b\x7f");
	});

	it("sends Escape-Return for the newline chord and a bare Return for submit", () => {
		expect(encodeKey(key({ key: "Enter" }))).toBe("\r");
		expect(encodeKey(key({ key: "Enter", shiftKey: true }))).toBe("\x1b\r");
	});

	it("leaves Command chords and bare modifiers to the application", () => {
		expect(encodeKey(key({ key: "k", metaKey: true }))).toBeNull();
		expect(encodeKey(key({ key: "Shift", shiftKey: true }))).toBeNull();
		expect(encodeKey(key({ key: "F13" }))).toBeNull();
	});
});
