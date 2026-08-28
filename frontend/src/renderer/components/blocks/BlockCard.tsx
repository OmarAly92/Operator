import { ChevronDown, ChevronRight } from "lucide-react";
import { memo, type ReactNode } from "react";
import { useTranslation } from "react-i18next";
import type { BlockAction } from "../../lib/block-actions";
import { blockDisplay, type BlockKind, type SessionBlock } from "../../lib/session-block";
import type { MatchRange } from "../../lib/text-match";
import { BlockStatusDot } from "./BlockStatusDot";
import type { MessageKey } from "../../i18n/messages";
import { Button } from "../ui/button";
import { Separator } from "../ui/separator";

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

const ACTION_KEY: Record<BlockAction["kind"], MessageKey> = {
	copy_block: "blocks.action.copyBlock",
	copy_command: "blocks.action.copyCommand",
	copy_output: "blocks.action.copyOutput",
	rerun: "blocks.action.rerun",
	rewind: "blocks.action.rewind",
};

export function BlockCardHeader({
	block,
	collapsed = false,
	onToggleCollapse,
}: {
	block: SessionBlock;
	collapsed?: boolean;
	onToggleCollapse?: (blockId: string) => void;
}) {
	const { t } = useTranslation();
	const display = blockDisplay(block);
	const content = (
		<>
			<BlockStatusDot status={block.status} />
			<span className="flex-1 truncate font-medium text-foreground text-xs">
				{display.displayName}
			</span>
			<span className="text-[10px] text-muted-foreground">{t(KIND_KEY[block.kind])}</span>
			{onToggleCollapse === undefined ? null : collapsed ? <ChevronRight className="size-3.5" /> : <ChevronDown className="size-3.5" />}
		</>
	);

	if (onToggleCollapse === undefined) {
		return <div className="flex items-center gap-2 border-border border-b px-3 py-2">{content}</div>;
	}

	return (
		<button
			aria-expanded={!collapsed}
			aria-label={t(collapsed ? "blocks.action.expand" : "blocks.action.collapse")}
			className="flex w-full items-center gap-2 border-border border-b px-3 py-2 text-left"
			onClick={() => onToggleCollapse(block.id)}
			type="button"
		>
			{content}
		</button>
	);
}

export const BlockCard = memo(function BlockCard({
	block,
	renderActions,
	actions,
	onAction,
	collapsed,
	onToggleCollapse,
}: {
	block: SessionBlock;
	renderActions?: (block: SessionBlock) => ReactNode;
	actions?: readonly BlockAction[];
	onAction?: (block: SessionBlock, action: BlockAction) => void;
	collapsed?: boolean;
	onToggleCollapse?: (blockId: string) => void;
	highlight?: { field: "displayName" | "summary"; ranges: readonly MatchRange[] };
	selected?: boolean;
	onToggleSelect?: (blockId: string, extend: boolean) => void;
}) {
	const { t } = useTranslation();
	const display = blockDisplay(block);
	const callerActions = renderActions?.(block);
	const hasCallerActions = callerActions !== undefined && callerActions !== null && callerActions !== false;
	const hasStandardActions = actions !== undefined && actions.length > 0;

	return (
		<div className="mx-3 my-1 rounded-md border border-border bg-card" data-testid="session-block">
			<BlockCardHeader block={block} collapsed={collapsed} onToggleCollapse={onToggleCollapse} />
			{collapsed ? null : (
				<>
			{display.summary === "" ? null : (
				<p className="whitespace-pre-wrap break-words px-3 py-2 font-mono text-muted-foreground text-xs">
					{display.summary}
				</p>
			)}
			{block.children !== undefined && block.children.length > 0 ? (
				<div className="border-border border-t px-3 py-2 pl-4" data-testid="session-block-children">
					{block.children.map((child) => (
						<BlockCard block={child} key={child.id} renderActions={renderActions} />
					))}
				</div>
			) : null}
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
			{!hasCallerActions && !hasStandardActions ? null : (
				<div className="flex gap-2 border-border border-t px-3 py-2" data-testid="block-actions">
					{hasCallerActions ? callerActions : null}
					{hasCallerActions && hasStandardActions ? <Separator orientation="vertical" /> : null}
					{actions?.map((action) => (
						<Button
							data-testid={`block-action-${action.kind}`}
							key={`${action.kind}-${action.turnId ?? action.payload ?? ""}`}
							onClick={() => onAction?.(block, action)}
							size="sm"
							variant={action.kind === "rewind" ? "outline" : "ghost"}
						>
							{t(ACTION_KEY[action.kind])}
						</Button>
					))}
				</div>
			)}
				</>
			)}
		</div>
	);
});
