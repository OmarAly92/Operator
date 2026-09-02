export type MouseReportKind = "press" | "release" | "drag" | "move" | "wheelUp" | "wheelDown";

export interface MouseModifiers {
	shift: boolean;
	alt: boolean;
	ctrl: boolean;
}

export interface MouseReportInput {
	kind: MouseReportKind;
	button: 0 | 1 | 2;
	column: number;
	row: number;
	sgrMouse: boolean;
	trackingLevel: number;
	modifiers: MouseModifiers;
	altScreen: boolean;
}

const TRACK_CLICK = 0b001;
const TRACK_DRAG = 0b010;
const TRACK_MOTION = 0b100;
const MOTION_BIT = 32;
const MOVE_BUTTON = 35;
const WHEEL_UP = 64;
const WHEEL_DOWN = 65;
const MOD_ALT = 8;
const MOD_CTRL = 16;

export function encodeMouseReport(input: MouseReportInput): string | null {
	if (input.modifiers.shift) return null;
	if (!input.sgrMouse) return null;
	const { kind, button, trackingLevel, altScreen } = input;
	const tracking = altScreen
		? trackingLevel | TRACK_CLICK | TRACK_DRAG | TRACK_MOTION
		: trackingLevel;
	if (tracking === 0) return null;
	let code: number;
	switch (kind) {
		case "press":
		case "release":
			if ((tracking & (TRACK_CLICK | TRACK_DRAG | TRACK_MOTION)) === 0) return null;
			code = button;
			break;
		case "drag":
			if ((tracking & (TRACK_DRAG | TRACK_MOTION)) === 0) return null;
			code = MOTION_BIT + button;
			break;
		case "move":
			if ((tracking & TRACK_MOTION) === 0) return null;
			code = MOVE_BUTTON;
			break;
		case "wheelUp":
			code = WHEEL_UP;
			break;
		case "wheelDown":
			code = WHEEL_DOWN;
			break;
	}
	if (input.modifiers.alt) code += MOD_ALT;
	if (input.modifiers.ctrl) code += MOD_CTRL;
	const final = kind === "release" ? "m" : "M";
	return `\x1b[<${code};${input.column};${input.row}${final}`;
}
