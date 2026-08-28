import {
	type FormEvent,
	useCallback,
	useEffect,
	useMemo,
	useRef,
	useState,
} from "react";
import { useTranslation } from "react-i18next";
import { Paperclip, SendHorizontal } from "lucide-react";
import { apiErrorMessage } from "../../lib/api-client";
import type { ChatSkill } from "../../types/conversation";
import { Button } from "../ui/button";
import { Input } from "../ui/input";
import { ComposerSuggestMenu } from "../chat/ComposerSuggestMenu";
import {
	findActiveTrigger,
	rankFiles,
	rankSkills,
	type Suggestion,
} from "../chat/composerSuggest";

export const BLOCK_MESSAGE_MAX_LENGTH = 4096;

export type BlockComposerSend = (input: { text: string }) => Promise<unknown>;
export type BlockComposerSteer = (text: string) => Promise<unknown> | void;
export type BlockComposerOnAttach = (files: File[]) => void | Promise<unknown>;

export function BlockComposer({
	sessionId,
	send,
	onAttach,
	suggestions: externalSuggestions,
	onSteer,
	canSteer,
	prefill,
}: {
	sessionId: string;
	send: BlockComposerSend;
	onAttach?: BlockComposerOnAttach;
	suggestions?: {
		trigger: string;
		query: string;
		items: Suggestion[];
	};
	onSteer?: BlockComposerSteer;
	canSteer?: boolean;
	prefill?: { text: string; revision: number };
}) {
	const { t } = useTranslation();
	const [draft, setDraft] = useState("");
	const [caret, setCaret] = useState(0);
	const [isSending, setIsSending] = useState(false);
	const [error, setError] = useState<string | undefined>(undefined);
	const generationRef = useRef(0);
	const filePicker = useRef<HTMLInputElement>(null);

	useEffect(() => {
		if (prefill === undefined) return;
		setDraft(prefill.text);
		setCaret(prefill.text.length);
	}, [prefill]);

	const trimmed = draft.trim();
	const canSubmit = trimmed.length > 0 && !isSending;
	const steering = canSteer === true && onSteer !== undefined && trimmed.length > 0;

	const submit = useCallback(
		async (event: FormEvent) => {
			event.preventDefault();
			if (!canSubmit || sessionId === "") return;
			const message = trimmed;
			const generation = generationRef.current;
			setIsSending(true);
			setError(undefined);
			try {
				if (steering && onSteer) {
					await onSteer(message);
				} else {
					await send({ text: message });
				}
				if (generationRef.current !== generation) return;
				setDraft("");
			} catch (cause) {
				if (generationRef.current !== generation) return;
				const message =
					cause instanceof Error ? cause.message : apiErrorMessage(cause, t("blocks.sendError"));
				setError(message);
			} finally {
				if (generationRef.current === generation) setIsSending(false);
			}
		},
		[canSubmit, onSteer, send, sessionId, steering, t, trimmed],
	);

	const activeTrigger = useMemo(
		() => (externalSuggestions === undefined ? findActiveTrigger(draft, caret) : undefined),
		[draft, caret, externalSuggestions],
	);
	const suggestionList: Suggestion[] = useMemo(() => {
		if (externalSuggestions !== undefined) return externalSuggestions.items;
		if (activeTrigger === undefined) return [];
		if (activeTrigger.kind === "skill") return rankSkills([] as ChatSkill[], activeTrigger.query);
		return rankFiles([], activeTrigger.query);
	}, [activeTrigger, externalSuggestions]);
	const menuOpen = suggestionList.length > 0;

	return (
		<form className="border-border border-t px-3 py-2" onSubmit={submit}>
			{error === undefined ? null : <p className="pb-1.5 text-[11px] text-destructive">{error}</p>}
			{menuOpen ? (
				<div className="mb-1.5">
					<ComposerSuggestMenu
						id={`block-composer-${sessionId}`}
						items={suggestionList}
						kind="skill"
						highlighted={0}
						onHighlight={() => {}}
						onPick={() => {}}
					/>
				</div>
			) : null}
			<div className="flex items-center gap-2">
				<Input
					aria-label={t("blocks.composerAria")}
					className="h-8 text-xs"
					disabled={isSending}
					maxLength={BLOCK_MESSAGE_MAX_LENGTH}
					onChange={(event) => {
						setDraft(event.target.value);
						setCaret(event.target.value.length);
					}}
					placeholder={
						steering
							? t("blocks.steerPlaceholder")
							: t("blocks.composerPlaceholder")
					}
					value={draft}
				/>
				{onAttach !== undefined ? (
					<>
						<input
							ref={filePicker}
							className="hidden"
							multiple
							onChange={(event) => {
								const files = Array.from(event.target.files ?? []);
								if (files.length > 0) void onAttach(files);
								event.target.value = "";
							}}
							type="file"
						/>
						<Button
							aria-label={t("blocks.attach")}
							data-testid="block-attach"
							onClick={() => filePicker.current?.click()}
							size="icon"
							type="button"
							variant="ghost"
						>
							<Paperclip className="size-4" />
						</Button>
					</>
				) : null}
				<Button
					aria-label={steering ? t("blocks.steer") : t("blocks.send")}
					data-testid="block-send"
					disabled={!canSubmit}
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
