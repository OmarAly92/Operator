import {
	closestCenter,
	DndContext,
	DragOverlay,
	KeyboardSensor,
	PointerSensor,
	pointerWithin,
	useDraggable,
	useDroppable,
	useSensor,
	useSensors,
	type CollisionDetection,
	type DragEndEvent,
	type DragStartEvent,
} from "@dnd-kit/core";
import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from "react";
import { dropAccepts, planDragId, type PlanDragData } from "../../lib/ticket-assign";
import { planNumber, type PlanView, type TicketWithProject } from "../../lib/ticket-presentation";
import { AssignPlanSheet } from "./AssignPlanSheet";

export type AssignRequest = PlanDragData;

type TicketDragContextValue = {
	active: PlanDragData | null;
	requestAssign: (ticket: TicketWithProject, plan: PlanView) => void;
};

const TicketDragContext = createContext<TicketDragContextValue>({ active: null, requestAssign: () => undefined });

export function useTicketDrag(): TicketDragContextValue {
	return useContext(TicketDragContext);
}

const collisionDetection: CollisionDetection = (args) => {
	const within = pointerWithin(args);
	return within.length > 0 ? within : closestCenter(args);
};

function dragData(event: { active: { data: { current?: unknown } } }): PlanDragData | null {
	const data = event.active.data.current as PlanDragData | undefined;
	return data && data.ticket && data.plan ? data : null;
}

export function TicketDndProvider({ children }: { children: ReactNode }) {
	const [active, setActive] = useState<PlanDragData | null>(null);
	const [pending, setPending] = useState<AssignRequest | null>(null);
	const sensors = useSensors(
		useSensor(PointerSensor, { activationConstraint: { distance: 4 } }),
		useSensor(KeyboardSensor),
	);
	const requestAssign = useCallback((ticket: TicketWithProject, plan: PlanView) => setPending({ ticket, plan }), []);
	const onDragStart = (event: DragStartEvent) => setActive(dragData(event));
	const onDragEnd = (event: DragEndEvent) => {
		const data = dragData(event);
		setActive(null);
		if (!data || !event.over) return;
		if (dropAccepts(String(event.over.id), data)) setPending(data);
	};
	const value = useMemo(() => ({ active, requestAssign }), [active, requestAssign]);

	return (
		<TicketDragContext.Provider value={value}>
			<DndContext
				sensors={sensors}
				collisionDetection={collisionDetection}
				onDragStart={onDragStart}
				onDragEnd={onDragEnd}
				onDragCancel={() => setActive(null)}
			>
				{children}
				<DragOverlay dropAnimation={null}>{active ? <PlanDragChip data={active} /> : null}</DragOverlay>
			</DndContext>
			{pending ? (
				<AssignPlanSheet
					open
					onOpenChange={(open) => !open && setPending(null)}
					ticket={pending.ticket}
					plan={pending.plan}
				/>
			) : null}
		</TicketDragContext.Provider>
	);
}

function PlanDragChip({ data }: { data: PlanDragData }) {
	const number = planNumber(data.plan.file);
	return (
		<div className="pointer-events-none inline-flex max-w-72 items-center gap-2 rounded-md border border-border-strong bg-surface px-2.5 py-1.5 text-2xs shadow-md">
			<span className="shrink-0 font-mono text-micro text-passive">{number || "·"}</span>
			<span className="min-w-0 truncate font-medium text-foreground">{data.plan.title}</span>
			<span className="shrink-0 font-mono text-micro text-passive">{data.ticket.slug}</span>
		</div>
	);
}

export function usePlanDraggable(data: PlanDragData, enabled: boolean) {
	const { attributes, listeners, setNodeRef, setActivatorNodeRef, isDragging } = useDraggable({
		id: planDragId(data),
		data,
		disabled: !enabled,
	});
	return { attributes, listeners, setNodeRef, setActivatorNodeRef, isDragging };
}

export function useTicketDropTarget(id: string) {
	const { active } = useTicketDrag();
	const { setNodeRef, isOver } = useDroppable({ id });
	const accepts = active !== null && dropAccepts(id, active);
	return { setNodeRef, isOver: isOver && accepts, accepts, dragging: active !== null };
}
