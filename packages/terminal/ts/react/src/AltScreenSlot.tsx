import type { ReactElement, ReactNode } from "react";

export interface AltScreenSlotProps {
	readonly blockList: ReactNode;
	readonly surface?: ReactNode;
	readonly active: boolean;
}

export function AltScreenSlot({
	blockList,
	surface,
	active,
}: AltScreenSlotProps): ReactElement {
	const showSurface = active && surface !== undefined;
	return (
		<>
			<div hidden={showSurface} aria-hidden={showSurface}>
				{blockList}
			</div>
			{surface !== undefined ? (
				<div hidden={!showSurface} aria-hidden={!showSurface}>
					{surface}
				</div>
			) : null}
		</>
	);
}
