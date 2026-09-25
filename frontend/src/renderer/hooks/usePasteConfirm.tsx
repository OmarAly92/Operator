import { useCallback, useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import type { PasteUnsafeReason } from "@operator/terminal-react";
import { ConfirmDialog } from "../components/ConfirmDialog";

export type PasteConfirmFn = (preview: string, reason: PasteUnsafeReason) => Promise<boolean>;

type PendingPaste = Readonly<{
	preview: string;
	reason: PasteUnsafeReason;
	resolve: (accepted: boolean) => void;
}>;

const PREVIEW_LINES = 5;
const PREVIEW_LINE_CHARS = 200;

const reasonKeys = {
	newline: "terminal.pasteReasonNewline",
	control: "terminal.pasteReasonControl",
	"paste-end": "terminal.pasteReasonPasteEnd",
} as const satisfies Record<PasteUnsafeReason, string>;

export function pastePreviewLines(preview: string): { lines: string[]; hidden: number } {
	const all = preview.split("\n");
	return {
		lines: all
			.slice(0, PREVIEW_LINES)
			.map((line) => (line.length > PREVIEW_LINE_CHARS ? `${line.slice(0, PREVIEW_LINE_CHARS)}…` : line)),
		hidden: Math.max(0, all.length - PREVIEW_LINES),
	};
}

export function usePasteConfirm() {
	const { t } = useTranslation();
	const [pending, setPending] = useState<PendingPaste | null>(null);
	const pendingRef = useRef<PendingPaste | null>(null);

	const settle = useCallback((accepted: boolean) => {
		const current = pendingRef.current;
		pendingRef.current = null;
		setPending(null);
		current?.resolve(accepted);
	}, []);

	useEffect(() => () => settle(false), [settle]);

	const confirmPaste = useCallback<PasteConfirmFn>(
		(preview, reason) =>
			new Promise<boolean>((resolve) => {
				pendingRef.current?.resolve(false);
				const next: PendingPaste = { preview, reason, resolve };
				pendingRef.current = next;
				setPending(next);
			}),
		[],
	);

	const shown = pending ? pastePreviewLines(pending.preview) : null;
	const dialog = (
		<ConfirmDialog
			open={pending !== null}
			title={t("terminal.pasteConfirmTitle")}
			description={
				pending && shown ? (
					<>
						<p>{t(reasonKeys[pending.reason])}</p>
						<pre
							data-testid="paste-preview"
							className="mt-2 max-h-40 overflow-auto whitespace-pre-wrap break-all rounded-md border border-(--color-border-settings-dialog) p-2 font-mono text-caption text-settings-label"
						>
							{shown.lines.join("\n")}
						</pre>
						{shown.hidden > 0 ? (
							<p className="mt-1">{t("terminal.pasteMoreLines", { count: shown.hidden })}</p>
						) : null}
					</>
				) : null
			}
			confirmLabel={t("terminal.pasteConfirm")}
			onConfirm={() => settle(true)}
			onOpenChange={(open) => {
				if (!open) settle(false);
			}}
		/>
	);

	return { confirmPaste, dialog };
}
