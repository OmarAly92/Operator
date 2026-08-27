import { cn } from "../../lib/utils";
import type { BlockStatus } from "../../lib/session-block";

const STATUS_CLASS: Record<BlockStatus, string> = {
	running: "bg-primary",
	ok: "bg-success",
	failed: "bg-destructive",
	blocked: "bg-warning",
};

export function BlockStatusDot({ status }: { status: BlockStatus }) {
	return (
		<span
			className={cn("size-1.5 shrink-0 rounded-full", STATUS_CLASS[status])}
			data-status={status}
			data-testid="block-status-dot"
		/>
	);
}
