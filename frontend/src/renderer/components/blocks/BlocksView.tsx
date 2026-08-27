import { useEffect, useLayoutEffect, useRef } from "react";
import { useTranslation } from "react-i18next";
import type { SessionBlock } from "../../lib/session-block";
import { Button } from "../ui/button";
import { BlockCard } from "./BlockCard";

export type BlocksViewProps = {
	blocks: SessionBlock[];
	isLoading: boolean;
	isLoadingOlder: boolean;
	hasOlder: boolean;
	error?: string;
	harness?: string;
	supported: boolean;
	onLoadOlder: () => void;
	onRetry: () => void;
};

const PINNED_SLACK_PX = 24;

export function BlocksView({
	blocks,
	isLoading,
	isLoadingOlder,
	hasOlder,
	error,
	harness,
	supported,
	onLoadOlder,
	onRetry,
}: BlocksViewProps) {
	const { t } = useTranslation();
	const scrollRef = useRef<HTMLDivElement | null>(null);
	const pinnedRef = useRef(true);

	useEffect(() => {
		const node = scrollRef.current;
		if (!node) return;
		const onScroll = () => {
			pinnedRef.current = node.scrollTop + node.clientHeight >= node.scrollHeight - PINNED_SLACK_PX;
		};
		node.addEventListener("scroll", onScroll);
		return () => node.removeEventListener("scroll", onScroll);
	}, []);

	useLayoutEffect(() => {
		const node = scrollRef.current;
		if (!node || !pinnedRef.current) return;
		node.scrollTop = node.scrollHeight;
	}, [blocks]);

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
		<div
			aria-label={t("blocks.panelAria")}
			className="h-full min-h-0 overflow-y-auto py-1.5"
			ref={scrollRef}
			role="log"
		>
			{isLoadingOlder ? (
				<p className="py-2 text-center text-[11px] text-muted-foreground">{t("blocks.loadingOlder")}</p>
			) : hasOlder ? (
				<div className="flex justify-center py-1.5">
					<Button onClick={onLoadOlder} size="sm" variant="ghost">
						{t("blocks.loadOlder")}
					</Button>
				</div>
			) : null}
			{blocks.map((block) => (
				<BlockCard block={block} key={block.id} />
			))}
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
