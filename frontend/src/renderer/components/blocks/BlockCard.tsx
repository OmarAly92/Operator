import { useTranslation } from "react-i18next";
import type { BlockKind, SessionBlock } from "../../lib/session-block";
import { BlockStatusDot } from "./BlockStatusDot";
import type { MessageKey } from "../../i18n/messages";

const KIND_KEY: Record<BlockKind, MessageKey> = {
	prompt: "blocks.kind.prompt",
	assistant: "blocks.kind.assistant",
	tool: "blocks.kind.tool",
	permission: "blocks.kind.permission",
	notice: "blocks.kind.notice",
};

function blockTitleKey(block: SessionBlock) {
	switch (block.kind) {
		case "prompt":
			return "blocks.title.prompt" as const;
		case "assistant":
			return "blocks.title.assistant" as const;
		case "permission":
			return "blocks.title.permissionRequested" as const;
		case "tool":
			return block.title === "Tool" ? ("blocks.title.tool" as const) : undefined;
		case "notice":
			if (block.status === "blocked") return "blocks.title.waitingOnYou" as const;
			if (block.title === "Session started") return "blocks.title.sessionStarted" as const;
			if (block.title === "Event") return "blocks.title.event" as const;
			return undefined;
	}
}

export function BlockCard({ block }: { block: SessionBlock }) {
	const { t } = useTranslation();
	const titleKey = blockTitleKey(block);

	return (
		<div className="mx-3 my-1 rounded-md border border-border bg-card" data-testid="session-block">
			<div className="flex items-center gap-2 border-border border-b px-3 py-2">
				<BlockStatusDot status={block.status} />
				<span className="flex-1 truncate font-medium text-foreground text-xs">
					{titleKey ? t(titleKey) : block.title}
				</span>
				<span className="text-[10px] text-muted-foreground">{t(KIND_KEY[block.kind])}</span>
			</div>
			{block.body === "" ? null : (
				<p className="whitespace-pre-wrap break-words px-3 py-2 font-mono text-muted-foreground text-xs">
					{block.body}
				</p>
			)}
			{block.redacted ? (
				<p className="px-3 pb-1.5 text-[10px] text-warning">{t("blocks.redacted")}</p>
			) : null}
			{block.truncatedLines > 0 ? (
				<p className="px-3 pb-2 text-[10px] text-muted-foreground">
					{t("blocks.truncated", { count: block.truncatedLines })}
				</p>
			) : null}
		</div>
	);
}
