import { motion } from "motion/react";
import { createPortal } from "react-dom";
import { useTranslation } from "react-i18next";
import { useSplitDragStore } from "./split-drag-store";

const BOX_INSET = 8;
const SLIDE = { duration: 0.12, ease: [0.33, 1, 0.68, 1] } as const;

export function SplitDropOverlay() {
	const { t } = useTranslation();
	const drag = useSplitDragStore((state) => state.drag);
	const target = useSplitDragStore((state) => state.target);
	if (!drag) return null;
	const geometry = target
		? {
				left: target.box.left + BOX_INSET,
				top: target.box.top + BOX_INSET,
				width: Math.max(0, target.box.width - BOX_INSET * 2),
				height: Math.max(0, target.box.height - BOX_INSET * 2),
			}
		: null;
	return createPortal(
		<div aria-hidden="true" className="pointer-events-none fixed inset-0 z-overlay">
			<div className="absolute inset-0 bg-black/10" data-testid="split-drop-dim" />
			{geometry && target ? (
				<motion.div
					animate={geometry}
					className="absolute flex items-center justify-center overflow-hidden rounded-xl border-2 border-ring/80 bg-background/10 backdrop-blur-[6px]"
					data-testid="split-drop-box"
					initial={false}
					style={geometry}
					transition={SLIDE}
				>
					<span className="rounded-full bg-ring/50 px-3 py-1 text-control font-medium text-foreground shadow-sm">
						{target.kind === "split" ? t("split.splitView") : t("split.openHere")}
					</span>
				</motion.div>
			) : null}
		</div>,
		document.body,
	);
}
