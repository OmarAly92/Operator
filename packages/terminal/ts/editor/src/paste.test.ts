import { describe, expect, it, vi } from "vitest";
import {
	clipboardHasImage,
	deliverPaste,
	encodePaste,
	pastePreview,
	planPaste,
	type PasteConfirm,
	type PasteVerdict,
} from "./paste";

const owned = { owned: true, bracketedPaste: false };
const child = { owned: false, bracketedPaste: false };
const safe: PasteVerdict = { safe: true };
const newline: PasteVerdict = { safe: false, reason: "newline" };
const control: PasteVerdict = { safe: false, reason: "control" };
const pasteEnd: PasteVerdict = { safe: false, reason: "paste-end" };

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

describe("encodePaste", () => {
	type Case = Readonly<{ name: string; text: string; bracketed: boolean; data: string; verdict: PasteVerdict }>;
	const cases: readonly Case[] = [
		{ name: "a plain one-line paste", text: "ls -la", bracketed: false, data: "ls -la", verdict: safe },
		{ name: "a tab", text: "a\tb", bracketed: false, data: "a\tb", verdict: safe },
		{ name: "a multi-line paste outside brackets", text: "one\ntwo", bracketed: false, data: "one\rtwo", verdict: newline },
		{ name: "a trailing newline", text: "ls\n", bracketed: false, data: "ls\r", verdict: newline },
		{ name: "CRLF outside brackets", text: "one\r\ntwo", bracketed: false, data: "one\rtwo", verdict: newline },
		{ name: "a lone CR outside brackets", text: "one\rtwo", bracketed: false, data: "one\rtwo", verdict: newline },
		{ name: "an embedded ESC outside brackets", text: "a\x1bb", bracketed: false, data: "a\x1bb", verdict: control },
		{ name: "a ^C outside brackets", text: "a\x03b", bracketed: false, data: "a\x03b", verdict: control },
		{ name: "a NUL outside brackets", text: "a\x00b", bracketed: false, data: "a\x00b", verdict: control },
		{ name: "a control and a newline", text: "a\x1b\nb", bracketed: false, data: "a\x1b\rb", verdict: control },
		{ name: "the paste-end sequence outside brackets", text: "a\x1b[201~b\n", bracketed: false, data: "a\x1b[201~b\r", verdict: pasteEnd },
		{ name: "a multi-line paste inside brackets", text: "one\ntwo", bracketed: true, data: "\x1b[200~one\rtwo\x1b[201~", verdict: safe },
		{ name: "CRLF inside brackets", text: "one\r\ntwo", bracketed: true, data: "\x1b[200~one\rtwo\x1b[201~", verdict: safe },
		{ name: "an ESC inside brackets", text: "a\x1bb", bracketed: true, data: "\x1b[200~ab\x1b[201~", verdict: safe },
		{ name: "a ^C inside brackets", text: "a\x03b", bracketed: true, data: "\x1b[200~ab\x1b[201~", verdict: safe },
		{ name: "the paste-end sequence inside brackets", text: "a\x1b[201~rm -rf /", bracketed: true, data: "\x1b[200~arm -rf /\x1b[201~", verdict: safe },
		{ name: "a paste-end hidden inside another", text: "\x1b[20\x1b[201~1~x", bracketed: true, data: "\x1b[200~[201~x\x1b[201~", verdict: safe },
		{ name: "a tab inside brackets", text: "a\tb", bracketed: true, data: "\x1b[200~a\tb\x1b[201~", verdict: safe },
	];

	it.each(cases)("$name", ({ text, bracketed, data, verdict }) => {
		expect(encodePaste(text, bracketed)).toEqual({ data, verdict });
	});
});

describe("pastePreview", () => {
	it("shows each carriage return as a line break", () => {
		expect(pastePreview("one\rtwo\r\nthree")).toBe("one\ntwo\nthree");
	});

	it("makes control characters visible as caret notation and keeps tabs", () => {
		expect(pastePreview("a\x1b[31mb\x03\tc\x7f\x00")).toBe("a^[[31mb^C\tc^?^@");
	});
});

describe("deliverPaste", () => {
	const unsafe = { kind: "send", data: "one\rtwo", verdict: newline } as const;

	it("sends a safe paste at once and never asks", async () => {
		const sent: string[] = [];
		const confirm = vi.fn<PasteConfirm>(async () => false);
		const delivered = deliverPaste({ kind: "send", data: "hello", verdict: safe }, (data) => sent.push(data), confirm);
		expect(sent).toEqual(["hello"]);
		await expect(delivered).resolves.toBe(true);
		expect(confirm).not.toHaveBeenCalled();
	});

	it("sends an unsafe paste at once when the host has no confirm, as before", async () => {
		const sent: string[] = [];
		const delivered = deliverPaste(unsafe, (data) => sent.push(data));
		expect(sent).toEqual(["one\rtwo"]);
		await expect(delivered).resolves.toBe(true);
	});

	it("asks with a readable preview and the reason, then sends the exact bytes once", async () => {
		const sent: string[] = [];
		const confirm = vi.fn<PasteConfirm>(async () => true);
		const delivered = deliverPaste(unsafe, (data) => sent.push(data), confirm);
		expect(sent).toEqual([]);
		await expect(delivered).resolves.toBe(true);
		expect(confirm).toHaveBeenCalledTimes(1);
		expect(confirm).toHaveBeenCalledWith("one\ntwo", "newline");
		expect(sent).toEqual(["one\rtwo"]);
	});

	it("sends nothing when the user declines", async () => {
		const sent: string[] = [];
		const delivered = deliverPaste(unsafe, (data) => sent.push(data), vi.fn<PasteConfirm>(async () => false));
		await expect(delivered).resolves.toBe(false);
		expect(sent).toEqual([]);
	});

	it("sends nothing when the confirm rejects", async () => {
		const sent: string[] = [];
		const confirm = vi.fn<PasteConfirm>(async () => {
			throw new Error("dialog closed");
		});
		await expect(deliverPaste(unsafe, (data) => sent.push(data), confirm)).resolves.toBe(false);
		expect(sent).toEqual([]);
	});

	it("sends nothing when the confirm throws", async () => {
		const sent: string[] = [];
		const confirm = vi.fn<PasteConfirm>(() => {
			throw new Error("no dialog");
		});
		await expect(deliverPaste(unsafe, (data) => sent.push(data), confirm)).resolves.toBe(false);
		expect(sent).toEqual([]);
	});

	it("sends nothing for a plan that inserts or does nothing", async () => {
		const sent: string[] = [];
		await expect(deliverPaste({ kind: "insert", text: "x" }, (data) => sent.push(data))).resolves.toBe(false);
		await expect(deliverPaste({ kind: "none" }, (data) => sent.push(data))).resolves.toBe(false);
		expect(sent).toEqual([]);
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

	it("never judges what goes into the editor, since nothing runs before Enter", () => {
		expect(planPaste({ text: "rm -rf /\x1b\x03\n", hasImage: false, ...owned })).toEqual({
			kind: "insert",
			text: "rm -rf /\x1b\x03\n",
		});
	});

	it("sends the text to a child that owns the line", () => {
		expect(planPaste({ text: "hello", hasImage: false, ...child })).toEqual({
			kind: "send",
			data: "hello",
			verdict: safe,
		});
	});

	// A pty takes CR, not LF: pasting "a\nb" as LF leaves the shell waiting on a
	// line it never sees end.
	it("turns newlines into carriage returns for a child and marks them unsafe", () => {
		expect(planPaste({ text: "one\r\ntwo\nthree", hasImage: false, ...child })).toEqual({
			kind: "send",
			data: "one\rtwo\rthree",
			verdict: newline,
		});
	});

	it("brackets the paste for a program that asked for it", () => {
		expect(
			planPaste({ text: "one\ntwo", hasImage: false, owned: false, bracketedPaste: true }),
		).toEqual({ kind: "send", data: "\x1b[200~one\rtwo\x1b[201~", verdict: safe });
	});

	// The escape would end the bracket early and the rest of the paste would run
	// as typed input. xterm drops it; so do we.
	it("strips a closing bracket hidden in the pasted text", () => {
		expect(
			planPaste({ text: "a\x1b[201~rm -rf /", hasImage: false, owned: false, bracketedPaste: true }),
		).toEqual({ kind: "send", data: "\x1b[200~arm -rf /\x1b[201~", verdict: safe });
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
			verdict: safe,
		});
	});

	it("prefers the text when the clipboard carries both", () => {
		expect(planPaste({ text: "caption", hasImage: true, ...child })).toEqual({
			kind: "send",
			data: "caption",
			verdict: safe,
		});
	});

	it("has nowhere to put an image while the editor owns the line", () => {
		expect(planPaste({ text: "", hasImage: true, ...owned })).toEqual({ kind: "none" });
	});
});
