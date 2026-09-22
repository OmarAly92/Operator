import { create } from "zustand";
import type { DraggedTab, DropResolution } from "../../lib/split-drop";
import type { TabRef } from "../../lib/split-layout";

export type SplitDrag = { tab: TabRef; label: string; source: DraggedTab };

type SplitDragState = {
	drag: SplitDrag | null;
	target: DropResolution | null;
	begin: (drag: SplitDrag) => void;
	retarget: (target: DropResolution | null) => void;
	clear: () => void;
};

export const useSplitDragStore = create<SplitDragState>((set) => ({
	drag: null,
	target: null,
	begin: (drag) => set({ drag, target: null }),
	retarget: (target) => set({ target }),
	clear: () => set({ drag: null, target: null }),
}));
