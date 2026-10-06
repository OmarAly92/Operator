import type { PasteUnsafeReason } from "@operator/terminal-core";

export type PasteVerdict = Readonly<{ safe: true }> | Readonly<{ safe: false; reason: PasteUnsafeReason }>;

export type EncodedPaste = Readonly<{ data: string; verdict: PasteVerdict }>;

export type PasteConfirm = (preview: string, reason: PasteUnsafeReason) => Promise<boolean>;

export type PastePlan =
	| Readonly<{ kind: "insert"; text: string }>
	| Readonly<{ kind: "send"; data: string; verdict: PasteVerdict }>
	| Readonly<{ kind: "none" }>;

export type PasteInput = Readonly<{
	text: string;
	hasImage: boolean;
	owned: boolean;
	bracketedPaste: boolean;
}>;

const PASTE_START = "\x1b[200~";
const PASTE_END = "\x1b[201~";
const CTRL_V = "\x16";
const SAFE: PasteVerdict = { safe: true };
const UNSAFE_CONTROL = /[\x00-\x08\x0b\x0c\x0e-\x1f]/;
const BRACKET_BREAKERS = /[\x1b\x03]/g;
const PREVIEW_CONTROL = /[\x00-\x08\x0b-\x1f\x7f]/g;

export function encodePaste(text: string, bracketedPaste: boolean): EncodedPaste {
	const data = text.replace(/\r\n|\n/g, "\r");
	if (bracketedPaste) {
		const body = data.split(PASTE_END).join("").replace(BRACKET_BREAKERS, "");
		return { data: `${PASTE_START}${body}${PASTE_END}`, verdict: SAFE };
	}
	return { data, verdict: verdictFor(data) };
}

function verdictFor(data: string): PasteVerdict {
	if (data.includes(PASTE_END)) return { safe: false, reason: "paste-end" };
	if (UNSAFE_CONTROL.test(data)) return { safe: false, reason: "control" };
	if (data.includes("\r")) return { safe: false, reason: "newline" };
	return SAFE;
}

export function pastePreview(data: string): string {
	return data
		.replace(/\r\n?/g, "\n")
		.replace(PREVIEW_CONTROL, (char) =>
			char === "\x7f" ? "^?" : `^${String.fromCharCode(char.charCodeAt(0) + 64)}`,
		);
}

export function deliverPaste(
	plan: PastePlan,
	send: (data: string) => void,
	confirm?: PasteConfirm,
): Promise<boolean> {
	if (plan.kind !== "send") return Promise.resolve(false);
	const { data, verdict } = plan;
	if (verdict.safe || !confirm) {
		send(data);
		return Promise.resolve(true);
	}
	const reason = verdict.reason;
	return Promise.resolve()
		.then(() => confirm(pastePreview(data), reason))
		.then(
			(accepted) => {
				if (accepted !== true) return false;
				send(data);
				return true;
			},
			() => false,
		);
}

export function planPaste(input: PasteInput): PastePlan {
	const { text, hasImage, owned, bracketedPaste } = input;
	if (text.length > 0) {
		if (owned) return { kind: "insert", text: text.replace(/\r\n?/g, "\n") };
		return { kind: "send", ...encodePaste(text, bracketedPaste) };
	}
	if (hasImage && !owned) return { kind: "send", data: CTRL_V, verdict: SAFE };
	return { kind: "none" };
}

// WebKit reports an image paste as the type "Files" with an image item behind
// it, Chromium as "image/png". Both shapes have to count or the same clipboard
// pastes on one engine and not the other.
export function clipboardHasImage(data: DataTransfer | null): boolean {
	if (!data) return false;
	for (const type of data.types) {
		if (type.startsWith("image/")) return true;
	}
	if (Array.from(data.files ?? []).some((file) => file.type.startsWith("image/"))) return true;
	return Array.from(data.items ?? []).some(
		(item) => item.kind === "file" && item.type.startsWith("image/"),
	);
}
