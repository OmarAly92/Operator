import { describe, expect, it } from "vitest";
import { clipboardHasImage, planPaste } from "./paste";

const owned = { owned: true, bracketedPaste: false };
const child = { owned: false, bracketedPaste: false };

describe("clipboardHasImage", () => {
	const transfer = (over: Partial<DataTransfer>) =>
		({ types: [], files: [], items: [], ...over }) as unknown as DataTransfer;

	it("sees Chromium's image type", () => {
		expect(clipboardHasImage(transfer({ types: ["image/png"] }))).toBe(true);
	});

	it("sees WebKit's file item behind a bare Files type", () => {
		expect(
			clipboardHasImage(
				transfer({
					types: ["Files"],
					items: [{ kind: "file", type: "image/png" }] as unknown as DataTransferItemList,
				}),
			),
		).toBe(true);
	});

	it("does not mistake a pasted text file for an image", () => {
		expect(
			clipboardHasImage(
				transfer({
					types: ["Files"],
					items: [{ kind: "file", type: "text/csv" }] as unknown as DataTransferItemList,
				}),
			),
		).toBe(false);
	});
});

describe("planPaste", () => {
	it("edits locally while the editor owns the line", () => {
		expect(planPaste({ text: "ls -la", hasImage: false, ...owned })).toEqual({
			kind: "insert",
			text: "ls -la",
		});
	});

	it("keeps newlines as newlines in the editor, where they are not submissions", () => {
		expect(planPaste({ text: "one\r\ntwo", hasImage: false, ...owned })).toEqual({
			kind: "insert",
			text: "one\ntwo",
		});
	});

	it("sends the text to a child that owns the line", () => {
		expect(planPaste({ text: "hello", hasImage: false, ...child })).toEqual({
			kind: "send",
			data: "hello",
		});
	});

	// A pty takes CR, not LF: pasting "a\nb" as LF leaves the shell waiting on a
	// line it never sees end.
	it("turns newlines into carriage returns for a child", () => {
		expect(planPaste({ text: "one\r\ntwo\nthree", hasImage: false, ...child })).toEqual({
			kind: "send",
			data: "one\rtwo\rthree",
		});
	});

	it("brackets the paste for a program that asked for it", () => {
		expect(
			planPaste({ text: "one\ntwo", hasImage: false, owned: false, bracketedPaste: true }),
		).toEqual({ kind: "send", data: "\x1b[200~one\rtwo\x1b[201~" });
	});

	// The escape would end the bracket early and the rest of the paste would run
	// as typed input. xterm drops it; so do we.
	it("strips a closing bracket hidden in the pasted text", () => {
		expect(
			planPaste({ text: "a\x1b[201~rm -rf /", hasImage: false, owned: false, bracketedPaste: true }),
		).toEqual({ kind: "send", data: "\x1b[200~arm -rf /\x1b[201~" });
	});

	it("does nothing for an empty clipboard", () => {
		expect(planPaste({ text: "", hasImage: false, ...child })).toEqual({ kind: "none" });
	});

	// A pty carries bytes, so an image cannot be sent. Claude Code reads the
	// system clipboard itself when it sees Ctrl+V, which is exactly what an
	// image paste should turn into for the program holding the line.
	it("hands an image to the child as Ctrl+V so it can read the clipboard itself", () => {
		expect(planPaste({ text: "", hasImage: true, ...child })).toEqual({
			kind: "send",
			data: "\x16",
		});
	});

	it("prefers the text when the clipboard carries both", () => {
		expect(planPaste({ text: "caption", hasImage: true, ...child })).toEqual({
			kind: "send",
			data: "caption",
		});
	});

	it("has nowhere to put an image while the editor owns the line", () => {
		expect(planPaste({ text: "", hasImage: true, ...owned })).toEqual({ kind: "none" });
	});
});
