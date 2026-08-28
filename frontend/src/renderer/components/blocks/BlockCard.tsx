import { memo } from "react";
import { useTranslation } from "react-i18next";
import { blockDisplay, type BlockKind, type SessionBlock } from "../../lib/session-block";
import { BlockStatusDot } from "./BlockStatusDot";
import type { MessageKey } from "../../i18n/messages";
import { Button } from "../ui/button";

const KIND_KEY: Record<BlockKind, MessageKey> = {
	prompt: "blocks.kind.prompt",
	assistant: "blocks.kind.assistant",
	reasoning: "blocks.kind.assistant",
	tool: "blocks.kind.tool",
	todo: "blocks.kind.tool",
	compaction: "blocks.kind.notice",
	permission: "blocks.kind.permission",
	notice: "blocks.kind.notice",
};

export function BlockCardHeader({ block }: { block: SessionBlock }) {
	const { t } = useTranslation();
	const display = blockDisplay(block);

	return (
		<div className="flex items-center gap-2 border-border border-b px-3 py-2">
			<BlockStatusDot status={block.status} />
			<span className="flex-1 truncate font-medium text-foreground text-xs">
				{display.displayName}
			</span>
			<span className="text-[10px] text-muted-foreground">{t(KIND_KEY[block.kind])}</span>
		</div>
	);
}

export const BlockCard = memo(function BlockCard({
	block,
	permissionKind,
	onApprove,
	onDecline,
	onAnswer,
}: {
	block: SessionBlock;
	permissionKind?: "approval" | "user_input";
	onApprove?: (requestId: string, decisionId: string) => void;
	onDecline?: (requestId: string, decisionId: string) => void;
	onAnswer?: (requestId: string) => void;
}) {
	const { t } = useTranslation();
	const display = blockDisplay(block);
	const showApprovalActions =
		block.kind === "permission" && permissionKind === "approval" && block.status === "blocked";
	const showAnswerAction =
		block.kind === "permission" && permissionKind === "user_input" && block.status === "blocked";
	const requestId = block.id;

	return (
		<div className="mx-3 my-1 rounded-md border border-border bg-card" data-testid="session-block">
			<BlockCardHeader block={block} />
			{display.summary === "" ? null : (
				<p className="whitespace-pre-wrap break-words px-3 py-2 font-mono text-muted-foreground text-xs">
					{display.summary}
				</p>
			)}
			{display.errorText === undefined ? null : (
				<p className="px-3 pb-1.5 text-[10px] text-destructive">{display.errorText}</p>
			)}
			{block.redacted ? (
				<p className="px-3 pb-1.5 text-[10px] text-warning">{t("blocks.redacted")}</p>
			) : null}
			{block.truncatedLines > 0 ? (
				<p className="px-3 pb-2 text-[10px] text-muted-foreground">
					{t("blocks.truncated", { count: block.truncatedLines })}
				</p>
			) : null}
			{showApprovalActions && (onApprove !== undefined || onDecline !== undefined) ? (
				<div className="flex gap-2 border-border border-t px-3 py-2">
					{onApprove !== undefined ? (
						<Button
							aria-label={t("blocks.approve")}
							data-testid="block-approve"
							onClick={() => onApprove(requestId, "approve")}
							size="sm"
							variant="primary"
						>
							{t("blocks.approve")}
						</Button>
					) : null}
					{onDecline !== undefined ? (
						<Button
							aria-label={t("blocks.deny")}
							data-testid="block-decline"
							onClick={() => onDecline(requestId, "decline")}
							size="sm"
							variant="outline"
						>
							{t("blocks.deny")}
						</Button>
					) : null}
				</div>
			) : null}
			{showAnswerAction && onAnswer !== undefined ? (
				<div className="flex gap-2 border-border border-t px-3 py-2">
					<Button
						aria-label={t("blocks.answer")}
						data-testid="block-answer"
						onClick={() => onAnswer(requestId)}
						size="sm"
						variant="primary"
					>
						{t("blocks.answer")}
					</Button>
				</div>
			) : null}
		</div>
	);
});
