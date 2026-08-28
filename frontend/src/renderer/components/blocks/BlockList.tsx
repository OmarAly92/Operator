import { useVirtualizer } from "@tanstack/react-virtual";
import { ArrowDown, ChevronDown, ChevronUp } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import {
	BLOCK_OVERSCAN,
	ESTIMATED_BLOCK_HEIGHT,
	headerSticks,
	isPinned,
	nextBoundary,
	previousTarget,
	topItemFor,
} from "../../lib/block-viewport";
import { groupBlocksByTurn, type TurnGroup } from "../../lib/block-turns";
import type { SessionBlock } from "../../lib/session-block";
import { BlockCard, BlockCardHeader } from "./BlockCard";
import { Button } from "../ui/button";

export function BlockList({ blocks, sessionId }: { blocks: SessionBlock[]; sessionId: string }) {
	const { t } = useTranslation();
	const scrollRef = useRef<HTMLDivElement | null>(null);
	const pinnedRef = useRef(true);
	const [pinned, setPinned] = useState(true);
	const [stickyIndex, setStickyIndex] = useState<number | null>(null);

	const virtualizer = useVirtualizer({
		count: blocks.length,
		getScrollElement: () => scrollRef.current,
		estimateSize: () => ESTIMATED_BLOCK_HEIGHT,
		getItemKey: (index) => blocks[index]?.id ?? index,
		anchorTo: "end",
		followOnAppend: true,
		overscan: BLOCK_OVERSCAN,
	});
	const groupEndingByBlockId = useMemo(() => {
		const endings = new Map<string, TurnGroup>();
		for (const group of groupBlocksByTurn(blocks)) endings.set(group.blocks.at(-1)!.id, group);
		return endings;
	}, [blocks]);

	const sync = useCallback(() => {
		const node = scrollRef.current;
		if (node === null) return;
		const next = isPinned(node.scrollTop, virtualizer.getTotalSize(), node.clientHeight);
		pinnedRef.current = next;
		setPinned(next);

		const top = topItemFor(virtualizer.getVirtualItems(), node.scrollTop);
		setStickyIndex(
			top !== undefined && headerSticks(top.size, node.clientHeight) ? top.index : null,
		);
	}, [virtualizer]);

	useEffect(() => {
		pinnedRef.current = true;
		setPinned(true);
		setStickyIndex(null);
	}, [sessionId]);

	useEffect(() => {
		if (!pinnedRef.current || blocks.length === 0) return;
		virtualizer.scrollToOffset(virtualizer.getTotalSize(), { align: "start" });
	});

	const items = virtualizer.getVirtualItems();

	const node = scrollRef.current;
	const computedTop = node === null ? undefined : topItemFor(items, node.scrollTop);
	const computedSticky =
		computedTop !== undefined && node !== null && headerSticks(computedTop.size, node.clientHeight)
			? computedTop.index
			: null;
	const effectiveStickyIndex = node === null ? stickyIndex : computedSticky;

	const goNext = useCallback(() => {
		const target = nextBoundary(effectiveStickyIndex ?? undefined, blocks.length);
		if (target === undefined) return;
		virtualizer.scrollToIndex(target, { align: "start" });
	}, [blocks.length, effectiveStickyIndex, virtualizer]);

	const goPrevious = useCallback(() => {
		const node = scrollRef.current;
		if (node === null) return;
		const top = topItemFor(virtualizer.getVirtualItems(), node.scrollTop);
		const target = previousTarget(top, node.scrollTop, blocks.length);
		if (target === undefined) return;
		virtualizer.scrollToIndex(target, { align: "start" });
	}, [blocks.length, virtualizer]);

	const goLatest = useCallback(() => {
		pinnedRef.current = true;
		setPinned(true);
		virtualizer.scrollToOffset(virtualizer.getTotalSize(), { align: "start" });
	}, [virtualizer]);

	const stickyBlock = effectiveStickyIndex === null ? undefined : blocks[effectiveStickyIndex];

	return (
		<div className="relative h-full min-h-0">
			<div
				aria-label={t("blocks.panelAria")}
				className="h-full min-h-0 overflow-y-auto py-1.5"
				data-block-scroll
				onScroll={sync}
				ref={scrollRef}
				role="log"
			>
				<div
					data-block-sizer
					style={{ height: virtualizer.getTotalSize(), position: "relative", width: "100%" }}
				>
					{items.map((row) => {
						const item = blocks[row.index];
						if (item === undefined) return null;
						const group = groupEndingByBlockId.get(item.id);
						return (
							<div
								data-block-id={item.id}
								data-block-start={row.start}
								data-index={row.index}
								key={row.key}
								ref={virtualizer.measureElement}
								style={{
									left: 0,
									position: "absolute",
									top: 0,
									transform: `translateY(${row.start}px)`,
									width: "100%",
								}}
							>
								<BlockCard block={item} />
								{group === undefined ? null : <TurnGroupStatus group={group} />}
							</div>
						);
					})}
				</div>
			</div>
			{stickyBlock === undefined ? null : (
				<div className="pointer-events-none absolute inset-x-0 top-1.5 px-3">
					<div
						className="overflow-hidden rounded-t-md border border-border bg-card"
						data-testid="sticky-block-header"
					>
						<BlockCardHeader block={stickyBlock} />
					</div>
				</div>
			)}
			<div className="absolute right-3 bottom-3 flex flex-col items-end gap-2">
				<div className="flex flex-col overflow-hidden rounded-md border border-border bg-card">
					<Button aria-label={t("blocks.previousBlock")} onClick={goPrevious} size="icon" variant="ghost">
						<ChevronUp className="size-4" />
					</Button>
					<Button aria-label={t("blocks.nextBlock")} onClick={goNext} size="icon" variant="ghost">
						<ChevronDown className="size-4" />
					</Button>
				</div>
				{pinned ? null : (
					<Button aria-label={t("blocks.jumpToLatest")} onClick={goLatest} size="sm" variant="primary">
						<ArrowDown className="size-3.5" />
						{t("blocks.jumpToLatest")}
					</Button>
				)}
			</div>
		</div>
	);
}

function TurnGroupStatus({ group }: { group: TurnGroup }) {
	const [now, setNow] = useState(() => Date.now());

	useEffect(() => {
		if (!group.running) return undefined;
		const timer = window.setInterval(() => setNow(Date.now()), 1000);
		return () => window.clearInterval(timer);
	}, [group.running]);

	const durationMs = group.running ? elapsedSince(group.startedAt, now) : group.durationMs;
	return (
		<div className="mx-3 mb-3 flex items-center gap-2 text-[10px] text-muted-foreground" data-testid="turn-group-status">
		<div className="h-px flex-1 bg-border" />
		<span>{group.running ? "RUNNING" : "FINISHED"}{durationMs === undefined ? "" : ` · ${formatDuration(durationMs)}`}</span>
		<div className="h-px flex-1 bg-border" />
		</div>
	);
}

function elapsedSince(startedAt: string | undefined, now: number): number | undefined {
	if (startedAt === undefined) return undefined;
	const start = Date.parse(startedAt);
	return Number.isNaN(start) ? undefined : Math.max(0, now - start);
}

function formatDuration(durationMs: number): string {
	const seconds = Math.floor(durationMs / 1000);
	if (seconds < 60) return `${seconds}s`;
	const minutes = Math.floor(seconds / 60);
	if (minutes < 60) return `${minutes}m ${seconds % 60}s`;
	return `${Math.floor(minutes / 60)}h ${minutes % 60}m`;
}
