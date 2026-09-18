import { AlertTriangle } from "lucide-react";
import { RadioGroup } from "radix-ui";
import { useEffect, useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { staleModifiedAt, ticketErrorMessage, useTicketMutations } from "../../hooks/useTicketMutations";
import type { TicketFile } from "../../hooks/useTicketsQuery";
import { formatTimeCompact } from "../../lib/format-time";
import { headingIndexBeforeLine } from "../../lib/markdown-scroll-sync";
import { splitFrontmatter } from "../../lib/ticket-presentation";
import { cn } from "../../lib/utils";
import { MarkdownBody } from "../MarkdownBody";
import { TopbarButton } from "../TopbarButton";
import { CodeMirrorField } from "./CodeMirrorField";

export type EditorMode = "edit" | "preview" | "split";

const SAVED_FLASH_MS = 1800;

export function TicketEditor({
	projectId,
	slug,
	path,
	file,
	isError,
	error,
	warning,
	leading,
	reload,
	onDirtyChange,
}: {
	projectId: string;
	slug: string;
	path: string;
	file: TicketFile | undefined;
	isError: boolean;
	error?: unknown;
	warning?: string;
	leading?: ReactNode;
	reload: () => Promise<unknown>;
	onDirtyChange?: (dirty: boolean) => void;
}) {
	const { t } = useTranslation();
	const { saveTicketFile } = useTicketMutations();
	const [mode, setMode] = useState<EditorMode>("preview");
	const [draft, setDraft] = useState<string | null>(null);
	const [loadedAt, setLoadedAt] = useState<string | undefined>(file?.modifiedAt);
	const [stale, setStale] = useState<string | null>(null);
	const [saveError, setSaveError] = useState<string | null>(null);
	const [savedAt, setSavedAt] = useState<number | null>(null);
	const [busy, setBusy] = useState(false);
	const savingRef = useRef(false);
	const previewRef = useRef<HTMLDivElement>(null);
	const followFrame = useRef<number | null>(null);
	const content = draft ?? file?.content ?? "";
	const dirty = draft !== null && draft !== (file?.content ?? "");

	useEffect(() => {
		onDirtyChange?.(dirty);
	}, [dirty, onDirtyChange]);

	useEffect(() => {
		if (!file || savingRef.current) return;
		if (loadedAt === undefined) {
			setLoadedAt(file.modifiedAt);
			return;
		}
		if (file.modifiedAt === loadedAt) return;
		if (dirty) {
			setStale(file.modifiedAt);
			return;
		}
		setLoadedAt(file.modifiedAt);
		setDraft(null);
		setStale(null);
	}, [dirty, file, loadedAt]);

	useEffect(() => {
		if (savedAt === null) return;
		const timeout = window.setTimeout(() => setSavedAt(null), SAVED_FLASH_MS);
		return () => window.clearTimeout(timeout);
	}, [savedAt]);

	const save = async (keepMine = false) => {
		if (!file || busy || (!dirty && !keepMine)) return;
		savingRef.current = true;
		setBusy(true);
		setSaveError(null);
		try {
			const saved = await saveTicketFile.mutateAsync({
				projectId,
				slug,
				path,
				content,
				ifUnmodifiedSince: keepMine ? undefined : loadedAt,
			});
			setDraft(null);
			setLoadedAt(saved.modifiedAt);
			setStale(null);
			setSavedAt(Date.now());
		} catch (err) {
			const modifiedAt = staleModifiedAt(err);
			if (modifiedAt) setStale(modifiedAt);
			else setSaveError(ticketErrorMessage(err, t, "tickets.editor.saveFailed"));
		} finally {
			savingRef.current = false;
			setBusy(false);
		}
	};

	const reloadFromDisk = () => {
		setDraft(null);
		setStale(null);
		setSaveError(null);
		if (file) setLoadedAt(file.modifiedAt);
		void reload();
	};

	const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
		if (event.defaultPrevented) return;
		if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
			event.preventDefault();
			void save();
		}
	};

	const followTopLine = (line: number) => {
		if (followFrame.current !== null) cancelAnimationFrame(followFrame.current);
		followFrame.current = requestAnimationFrame(() => {
			followFrame.current = null;
			const root = previewRef.current;
			if (!root) return;
			const index = headingIndexBeforeLine(content, line);
			if (index < 0) {
				root.scrollTop = 0;
				return;
			}
			root.querySelectorAll("h1, h2, h3, h4, h5, h6")[index]?.scrollIntoView({ block: "start" });
		});
	};

	useEffect(
		() => () => {
			if (followFrame.current !== null) cancelAnimationFrame(followFrame.current);
		},
		[],
	);

	const parsed = splitFrontmatter(content);
	const modes: Array<{ value: EditorMode; label: string }> = [
		{ value: "edit", label: t("tickets.editor.edit") },
		{ value: "preview", label: t("tickets.editor.preview") },
		{ value: "split", label: t("tickets.editor.split") },
	];
	const showEditor = mode !== "preview";
	const showPreview = mode !== "edit";

	const preview = (
		<div ref={previewRef} className="board-scrollbar min-h-0 flex-1 overflow-y-auto px-6 py-5" data-testid="ticket-file-preview">
			{warning ? (
				<p className="mb-4 flex items-start gap-1.5 rounded-md border border-warning/40 bg-warning/10 px-3 py-2 text-2xs text-warning" role="status">
					<AlertTriangle aria-hidden="true" className="mt-px size-icon-2xs shrink-0" />
					<span>{warning}</span>
				</p>
			) : null}
			{isError ? (
				<p className="text-2xs text-error" role="alert">
					{ticketErrorMessage(error, t, "tickets.fileLoadFailed")}
				</p>
			) : null}
			{parsed.fields.length > 0 ? (
				<dl
					aria-label={t("tickets.frontmatter")}
					className="mb-4 grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 rounded-md border border-border bg-surface px-3 py-2 font-mono text-micro"
				>
					{parsed.fields.map(([key, value]) => (
						<div key={key} className="contents">
							<dt className="text-passive">{key}</dt>
							<dd className="min-w-0 truncate text-foreground">{value}</dd>
						</div>
					))}
				</dl>
			) : null}
			{file ? <MarkdownBody body={parsed.body} className="max-w-3xl text-sm text-foreground" /> : null}
		</div>
	);

	return (
		<section className="flex min-w-0 flex-1 flex-col" onKeyDown={onKeyDown}>
			<div className="flex h-toolbar shrink-0 items-center gap-2 border-b border-border-strong px-4" data-testid="ticket-editor-toolbar">
				{leading}
				<span className="min-w-0 truncate font-mono text-2xs text-foreground">{path}</span>
				{dirty ? (
					<span aria-label={t("tickets.editor.unsaved")} className="size-dot-sm shrink-0 rounded-full bg-status-working" role="status" />
				) : null}
				<span className="min-w-0 flex-1" />
				<RadioGroup.Root
					aria-label={t("tickets.editor.mode")}
					className="settings-segment shrink-0"
					value={mode}
					onValueChange={(next) => setMode(next as EditorMode)}
				>
					{modes.map((option) => (
						<RadioGroup.Item key={option.value} value={option.value} className="settings-segment-item">
							{option.label}
						</RadioGroup.Item>
					))}
				</RadioGroup.Root>
				<span className="shrink-0 whitespace-nowrap font-mono text-micro text-passive">
					{savedAt !== null
						? t("tickets.editor.saved")
						: file
							? t("tickets.fileModified", { time: formatTimeCompact(file.modifiedAt) })
							: ""}
				</span>
				<TopbarButton variant="primary" disabled={!file || busy || !dirty} onClick={() => void save()}>
					{busy ? t("tickets.editor.saving") : t("tickets.editor.save")}
				</TopbarButton>
			</div>
			{stale ? (
				<div
					className="flex flex-wrap items-center gap-2 border-b border-warning/40 bg-warning/10 px-4 py-2 text-2xs text-warning"
					data-testid="ticket-file-stale"
					role="alert"
				>
					<AlertTriangle aria-hidden="true" className="size-icon-2xs shrink-0" />
					<span className="font-medium">{t("tickets.editor.staleTitle")}</span>
					<span className="text-warning/80">{t("tickets.editor.staleBody")}</span>
					<span className="flex-1" />
					<TopbarButton onClick={reloadFromDisk}>{t("tickets.editor.reload")}</TopbarButton>
					<TopbarButton variant="primary" disabled={busy} onClick={() => void save(true)}>
						{t("tickets.editor.keepMine")}
					</TopbarButton>
				</div>
			) : null}
			{saveError ? (
				<p className="border-b border-border-strong px-4 py-1.5 text-2xs text-error" role="alert">
					{saveError}
				</p>
			) : null}
			<div className={cn("flex min-h-0 flex-1", mode === "split" && "divide-x divide-border-strong")}>
				{showEditor && file ? (
					<div className={cn("flex min-h-0 min-w-0 flex-col", mode === "split" ? "flex-1 basis-1/2" : "flex-1")}>
						<CodeMirrorField
							value={content}
							onChange={setDraft}
							onSave={() => void save()}
							onTopLineChange={mode === "split" ? followTopLine : undefined}
							ariaLabel={t("tickets.editor.aria", { file: path })}
							autoFocus={mode === "edit"}
						/>
					</div>
				) : null}
				{showPreview ? (
					<div className={cn("flex min-h-0 min-w-0 flex-col", mode === "split" ? "flex-1 basis-1/2" : "flex-1")}>{preview}</div>
				) : null}
			</div>
		</section>
	);
}
