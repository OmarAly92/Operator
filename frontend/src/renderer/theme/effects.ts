/**
 * Composed colour effects. These belong to the theme layer rather than to a
 * component: they mix a skin-owned colour rather than naming one, so a skin
 * still controls the result, but the recipe should live in one place.
 */

/**
 * The halo behind a status dot. Example: the pulsing blue dot on the
 * IDLE / WORKING column header of the board.
 */
export function dotGlow(color: string): string {
	return `0 0 7px color-mix(in srgb, ${color} 60%, transparent)`;
}

/**
 * The faint fill behind a status pill, tinted by the status colour. Example:
 * the wash behind "Needs you" on a session card.
 */
export function toneWash(color: string): string {
	return `color-mix(in srgb, ${color} 7%, transparent)`;
}

/**
 * The hairline ring around a status pill, drawn inside the box so it does not
 * change the pill's footprint. Example: the border of the same "Needs you" pill.
 */
export function toneRing(color: string): string {
	return `inset 0 0 0 1px color-mix(in srgb, ${color} 25%, transparent)`;
}
