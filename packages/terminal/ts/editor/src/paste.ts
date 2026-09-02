export type PastePlan =
	| Readonly<{ kind: "insert"; text: string }>
	| Readonly<{ kind: "send"; data: string }>
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

export function planPaste(input: PasteInput): PastePlan {
	const { text, hasImage, owned, bracketedPaste } = input;
	if (text.length > 0) {
		if (owned) return { kind: "insert", text: text.replace(/\r\n?/g, "\n") };
		const data = text.replace(/\r\n|\n/g, "\r");
		if (!bracketedPaste) return { kind: "send", data };
		return { kind: "send", data: `${PASTE_START}${data.split(PASTE_END).join("")}${PASTE_END}` };
	}
	if (hasImage && !owned) return { kind: "send", data: CTRL_V };
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
