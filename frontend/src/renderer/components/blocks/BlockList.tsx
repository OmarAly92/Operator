import { useVirtualizer } from "@tanstack/react-virtual";
import { useCallback, useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import {
	BLOCK_OVERSCAN,
	ESTIMATED_BLOCK_HEIGHT,
	isPinned,
	topItemFor,
} from "../../lib/block-viewport";
import type { SessionBlock } from "../../lib/session-block";
import { BlockCard } from "./BlockCard";

export function BlockList({ blocks, sessionId }: { blocks: SessionBlock[]; sessionId: string }) {
	const { t } = useTranslation();
	const scrollRef = useRef<HTMLDivElement | null>(null);
	const pinnedRef = useRef(true);
	const [pinned, setPinned] = useState(true);

	const virtualizer = useVirtualizer({
		count: blocks.length,
		getScrollElement: () => scrollRef.current,
		estimateSize: () => ESTIMATED_BLOCK_HEIGHT,
		getItemKey: (index) => blocks[index]?.id ?? index,
		anchorTo: "end",
		followOnAppend: true,
		overscan: BLOCK_OVERSCAN,
	});

	const sync = useCallback(() => {
		const node = scrollRef.current;
		if (node === null) return;
		const next = isPinned(node.scrollTop, virtualizer.getTotalSize(), node.clientHeight);
		pinnedRef.current = next;
		setPinned(next);
	}, [virtualizer]);

	useEffect(() => {
		pinnedRef.current = true;
		setPinned(true);
	}, [sessionId]);

	useEffect(() => {
		if (!pinnedRef.current || blocks.length === 0) return;
		virtualizer.scrollToOffset(virtualizer.getTotalSize(), { align: "start" });
	});

	const items = virtualizer.getVirtualItems();
	const scrollTop = scrollRef.current?.scrollTop ?? 0;
	void topItemFor(items, scrollTop);
	void pinned;

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
							</div>
						);
					})}
				</div>
			</div>
		</div>
	);
}
