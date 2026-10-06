import type { TerminalCore } from "@operator/terminal-core";

export const TYPEAHEAD_MAX_CHARS = 256;

export const CLEAR_SHELL_LINE = "\x15";

const CONTROL = /[\u0000-\u001f\u007f-\u009f]/u;

export function acceptTypeahead(text: string): string | null {
	if (text === "") return null;
	if ([...text].length > TYPEAHEAD_MAX_CHARS) return null;
	if (CONTROL.test(text)) return null;
	return text;
}

const SENT_LOG_CHARS = TYPEAHEAD_MAX_CHARS * 2;

export function sentAfterReport(sent: string, reported: string): string {
	const at = sent.lastIndexOf(reported);
	if (at === -1) return "";
	const rest = sent.slice(at + reported.length);
	return CONTROL.test(rest) ? "" : rest;
}

export class TypeaheadGate {
	private typed = false;
	private sent = "";

	reset(): void {
		this.typed = false;
		this.sent = "";
	}

	noteSent(data: string): void {
		if (data === "") return;
		this.typed = true;
		this.sent = (this.sent + data).slice(-SENT_LOG_CHARS);
	}

	take(core: TerminalCore): string | null {
		const reported = core.takeTypeahead();
		if (reported === "") return null;
		const accepted = this.typed ? acceptTypeahead(reported) : null;
		const sent = this.sent;
		this.reset();
		if (accepted === null) return null;
		return accepted + sentAfterReport(sent, accepted);
	}
}
