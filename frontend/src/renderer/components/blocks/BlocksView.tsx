import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import type { SessionBlock } from "../../lib/session-block";
import { Button } from "../ui/button";
import { BlockList } from "./BlockList";
import type { TurnGroup } from "../../lib/block-turns";

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
	onRollbackTurn,
	canRollbackTurn,
}: BlocksViewProps) {
	const { t } = useTranslation();

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
			<div className="min-h-0 flex-1">
				<BlockList
					blocks={blocks}
					canRollbackTurn={canRollbackTurn}
					onRollbackTurn={onRollbackTurn}
					renderActions={renderActions}
					sessionId={sessionId}
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
