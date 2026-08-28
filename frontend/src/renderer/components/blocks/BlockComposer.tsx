import { type FormEvent, useCallback, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { SendHorizontal } from "lucide-react";
import { apiErrorMessage } from "../../lib/api-client";
import { Button } from "../ui/button";
import { Input } from "../ui/input";

export const BLOCK_MESSAGE_MAX_LENGTH = 4096;

export type BlockComposerSend = (input: { text: string }) => Promise<unknown>;

export function BlockComposer({ sessionId, send }: { sessionId: string; send: BlockComposerSend }) {
	const { t } = useTranslation();
	const [draft, setDraft] = useState("");
	const [isSending, setIsSending] = useState(false);
	const [error, setError] = useState<string | undefined>(undefined);
	const generationRef = useRef(0);

	const submit = useCallback(
		async (event: FormEvent) => {
			event.preventDefault();
			const message = draft.trim();
			if (message === "" || isSending || sessionId === "") return;
			const generation = generationRef.current;
			setIsSending(true);
			setError(undefined);
			try {
				await send({ text: message });
				if (generationRef.current !== generation) return;
				setDraft("");
			} catch (cause) {
				if (generationRef.current !== generation) return;
				const message = cause instanceof Error ? cause.message : apiErrorMessage(cause, t("blocks.sendError"));
				setError(message);
			} finally {
				if (generationRef.current === generation) setIsSending(false);
			}
		},
		[draft, isSending, sessionId, send, t],
	);

	return (
		<form className="border-border border-t px-3 py-2" onSubmit={submit}>
			{error === undefined ? null : <p className="pb-1.5 text-[11px] text-destructive">{error}</p>}
			<div className="flex items-center gap-2">
				<Input
					aria-label={t("blocks.composerAria")}
					className="h-8 text-xs"
					disabled={isSending}
					maxLength={BLOCK_MESSAGE_MAX_LENGTH}
					onChange={(event) => setDraft(event.target.value)}
					placeholder={t("blocks.composerPlaceholder")}
					value={draft}
				/>
				<Button
					aria-label={t("blocks.send")}
					disabled={isSending || draft.trim() === ""}
					size="icon"
					type="submit"
					variant="primary"
				>
					<SendHorizontal className="size-4" />
				</Button>
			</div>
		</form>
	);
}
