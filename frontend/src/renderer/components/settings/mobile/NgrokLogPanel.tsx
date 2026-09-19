import { useEffect, useRef } from "react";
import { useTranslation } from "react-i18next";

import { cn } from "../../../lib/utils";
import { Button } from "../../ui/button";
import type { NgrokStatus } from "./useNgrok";

interface NgrokLogPanelProps {
	lines: NgrokStatus["logs"];
}

export function NgrokLogPanel({ lines }: NgrokLogPanelProps) {
	const { t } = useTranslation();
	const scrollRef = useRef<HTMLDivElement>(null);
	const scrolledUpRef = useRef(false);

	const onScroll = () => {
		const node = scrollRef.current;
		if (!node) return;
		scrolledUpRef.current = node.scrollHeight - node.scrollTop - node.clientHeight > 8;
	};

	useEffect(() => {
		const node = scrollRef.current;
		if (!node || scrolledUpRef.current) return;
		node.scrollTop = node.scrollHeight;
	}, [lines.length]);

	const copyLog = async () => {
		const text = lines.map((line) => [line.time, line.level, line.message].filter(Boolean).join(" ")).join("\n");
		try {
			await navigator.clipboard.writeText(text);
		} catch {
			return;
		}
	};

	return (
		<div className="flex flex-col gap-2 px-(--size-settings-row-padding-x) py-2">
			<div className="flex items-center justify-between">
				<span className="text-sm text-settings-label">{t("mobile.ngrok.agentLog")}</span>
				<Button type="button" variant="footer" size="sm" onClick={() => void copyLog()}>
					{t("mobile.ngrok.copyLog")}
				</Button>
			</div>
			<div
				ref={scrollRef}
				onScroll={onScroll}
				data-testid="ngrok-log-scroll"
				className="max-h-64 overflow-auto rounded-md border border-(--color-border-settings-input) bg-(--color-bg-settings-input) p-2 font-mono text-caption"
			>
				{lines.length === 0 ? (
					<span className="text-settings-muted">{t("mobile.ngrok.noLog")}</span>
				) : (
					lines.map((line, index) => (
						<div key={index} data-level={line.level}>
							<span className="text-settings-muted">{line.time}</span>{" "}
							<span className={cn(line.level === "eror" ? "text-error" : "text-settings-label")}>{line.message}</span>
						</div>
					))
				)}
			</div>
		</div>
	);
}
