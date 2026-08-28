import { useCallback, useEffect, useMemo, useState, type KeyboardEvent, type ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { blockActionsFor, type BlockAction, type BlockActionContext } from "../../lib/block-actions";
import type { SessionBlock } from "../../lib/session-block";
import { Button } from "../ui/button";
import { BlockList } from "./BlockList";
import type { TurnGroup } from "../../lib/block-turns";
import { FIND_CONTEXT_BLOCKS, filterBlocks, findBlockMatches, nextMatchId } from "../../lib/block-find";
import { BlockFindBar } from "./BlockFindBar";

const EMPTY_SET: ReadonlySet<string> = new Set();

export type BlocksViewProps = {
	blocks: SessionBlock[];
	isLoading: boolean;
	isLoadingOlder: boolean;
	hasOlder: boolean;
	error?: string;
	unavailable?: { code: string; message: string };
	harness?: string;
	sessionId: string;
	supported: boolean;
	onLoadOlder: () => void;
	onRetry: () => void;
	renderActions?: (block: SessionBlock) => ReactNode;
	actionContext: BlockActionContext;
	onAction: (block: SessionBlock, action: BlockAction) => void;
	onRollbackTurn?: (turnId: string) => void;
	canRollbackTurn?: (group: TurnGroup) => boolean;
};

export function BlocksView({
	blocks,
	isLoading,
	isLoadingOlder,
	hasOlder,
	error,
	unavailable,
	harness,
	sessionId,
	supported,
	onLoadOlder,
	onRetry,
	renderActions,
	actionContext,
	onAction,
	onRollbackTurn,
	canRollbackTurn,
}: BlocksViewProps) {
	const { t } = useTranslation();
	const [collapsedIds, setCollapsedIds] = useState<ReadonlySet<string>>(() => new Set());
	const [findOpen, setFindOpen] = useState(false);
	const [query, setQuery] = useState("");
	const [filtering, setFiltering] = useState(false);
	const [activeMatchId, setActiveMatchId] = useState<string | undefined>(undefined);
	useEffect(() => setCollapsedIds(new Set()), [sessionId]);
	const actionsByBlockId = useMemo(() => {
		const byBlockId = new Map<string, readonly BlockAction[]>();
		const add = (block: SessionBlock) => {
			byBlockId.set(block.id, blockActionsFor(block, actionContext));
			for (const child of block.children ?? []) add(child);
		};
		for (const block of blocks) add(block);
		return byBlockId;
	}, [actionContext, blocks]);
	const onToggleCollapse = useCallback((blockId: string) => {
		setCollapsedIds((current) => {
			const next = new Set(current);
			if (next.has(blockId)) next.delete(blockId);
			else next.add(blockId);
			return next;
		});
	}, []);
	const matches = useMemo(() => findBlockMatches(blocks, query), [blocks, query]);
	const filtered = useMemo(
		() => filtering && matches.length > 0 ? filterBlocks(blocks, query, FIND_CONTEXT_BLOCKS) : { blocks, matchIds: EMPTY_SET, hiddenCount: 0 },
		[blocks, filtering, matches.length, query],
	);
	const matchesByBlockId = useMemo(() => new Map(matches.map((match) => [match.blockId, match])), [matches]);
	const activeIndex = matches.findIndex((match) => match.blockId === activeMatchId);
	const closeFind = useCallback(() => {
		setFindOpen(false);
		setQuery("");
		setFiltering(false);
		setActiveMatchId(undefined);
	}, []);
	const onQueryChange = useCallback((nextQuery: string) => {
		setQuery(nextQuery);
		setActiveMatchId(findBlockMatches(blocks, nextQuery)[0]?.blockId);
	}, [blocks]);
	const stepMatch = useCallback((forward: boolean) => {
		setActiveMatchId((current) => nextMatchId(matches, current, forward));
	}, [matches]);
	const onFindKeyDown = useCallback((event: KeyboardEvent<HTMLDivElement>) => {
		if (!event.metaKey && !event.ctrlKey) return;
		if (event.key.toLowerCase() !== "f") return;
		event.preventDefault();
		setFindOpen(true);
	}, []);

	if (unavailable !== undefined) {
		return (
			<div className="flex h-full flex-col items-center justify-center gap-1 px-8 text-center">
				<p className="text-muted-foreground text-xs">{unavailable.message}</p>
				<p className="text-muted-foreground/70 text-[10px] font-mono">{unavailable.code}</p>
			</div>
		);
	}

	if (!supported) {
		return <Notice text={t("blocks.unavailable", { harness: harness ?? "" })} />;
	}

	if (error !== undefined && blocks.length === 0) {
		return (
			<div className="flex h-full flex-col items-center justify-center gap-2 px-8 text-center">
				<p className="text-destructive text-xs">{error}</p>
				<Button onClick={onRetry} size="sm" variant="outline">
					{t("blocks.retry")}
				</Button>
			</div>
		);
	}

	if (blocks.length === 0) {
		return <Notice text={isLoading ? t("blocks.loading") : t("blocks.empty")} />;
	}

	return (
		<div className="flex h-full min-h-0 flex-col">
			{isLoadingOlder ? (
				<p className="py-2 text-center text-[11px] text-muted-foreground">{t("blocks.loadingOlder")}</p>
			) : hasOlder ? (
				<div className="flex justify-center py-1.5">
					<Button onClick={onLoadOlder} size="sm" variant="ghost">
						{t("blocks.loadOlder")}
					</Button>
				</div>
			) : null}
			{findOpen ? (
				<BlockFindBar
					activeIndex={Math.max(activeIndex, 0)}
					filtering={filtering}
					matchCount={matches.length}
					onClose={closeFind}
					onNext={() => stepMatch(true)}
					onPrevious={() => stepMatch(false)}
					onQueryChange={onQueryChange}
					onToggleFilter={() => setFiltering((current) => !current)}
					query={query}
				/>
			) : null}
			{filtering && filtered.hiddenCount > 0 ? <p className="px-3 py-1 text-muted-foreground text-xs">{t("blocks.find.hidden", { count: filtered.hiddenCount })}</p> : null}
			<div className="min-h-0 flex-1">
				<BlockList
					activeMatchId={activeMatchId}
					blocks={filtered.blocks}
					actionsByBlockId={actionsByBlockId}
					canRollbackTurn={canRollbackTurn}
					collapsedIds={collapsedIds}
					onAction={onAction}
					onRollbackTurn={onRollbackTurn}
					onToggleCollapse={onToggleCollapse}
					onFindKeyDown={onFindKeyDown}
					renderActions={renderActions}
					sessionId={sessionId}
					matchesByBlockId={matchesByBlockId}
				/>
			</div>
		</div>
	);
}

function Notice({ text }: { text: string }) {
	return (
		<div className="flex h-full items-center justify-center px-8">
			<p className="text-center text-muted-foreground text-xs">{text}</p>
		</div>
	);
}
