const encoder = new TextEncoder();

const SETTLED_BEGIN = encoder.encode("\x1b]7000;v=1;settled=begin\x1b\\");
const SETTLED_END = encoder.encode("\x1b]7000;v=1;settled=end\x1b\\");
const FRAME_ORIGIN = encoder.encode("\x1b]7000;v=1;origin=");
const FRAME_READY = encoder.encode("\x1b]7000;v=1;ready=1\x1b\\");

const EMPTY = new Uint8Array(0);

export type SettledReplayFilter = {
	push: (bytes: Uint8Array) => Uint8Array;
};

function indexOf(haystack: Uint8Array, needle: Uint8Array, from: number): number {
	const last = haystack.length - needle.length;
	outer: for (let at = from; at <= last; at += 1) {
		for (let i = 0; i < needle.length; i += 1) {
			if (haystack[at + i] !== needle[i]) continue outer;
		}
		return at;
	}
	return -1;
}

function partialTail(bytes: Uint8Array, from: number, needles: readonly Uint8Array[]): number {
	let longest = 0;
	for (const needle of needles) {
		const most = Math.min(needle.length - 1, bytes.length - from);
		for (let length = most; length > longest; length -= 1) {
			const start = bytes.length - length;
			let matches = true;
			for (let i = 0; i < length; i += 1) {
				if (bytes[start + i] !== needle[i]) {
					matches = false;
					break;
				}
			}
			if (matches) {
				longest = length;
				break;
			}
		}
	}
	return longest;
}

function concat(parts: readonly Uint8Array[]): Uint8Array {
	if (parts.length === 1) return parts[0]!;
	const total = parts.reduce((sum, part) => sum + part.length, 0);
	const out = new Uint8Array(total);
	let at = 0;
	for (const part of parts) {
		out.set(part, at);
		at += part.length;
	}
	return out;
}

export function createSettledReplayFilter(): SettledReplayFilter {
	let carry = EMPTY;
	let dropping = false;
	return {
		push(bytes) {
			const data = carry.length > 0 ? concat([carry, bytes]) : bytes;
			carry = EMPTY;
			const kept: Uint8Array[] = [];
			let at = 0;
			while (at <= data.length) {
				if (!dropping) {
					const begin = indexOf(data, SETTLED_BEGIN, at);
					if (begin >= 0) {
						kept.push(data.subarray(at, begin));
						at = begin + SETTLED_BEGIN.length;
						dropping = true;
						continue;
					}
					const held = partialTail(data, at, [SETTLED_BEGIN]);
					kept.push(data.subarray(at, data.length - held));
					carry = data.slice(data.length - held);
					break;
				}
				const end = indexOf(data, SETTLED_END, at);
				const origin = indexOf(data, FRAME_ORIGIN, at);
				const ready = indexOf(data, FRAME_READY, at);
				const resume = [origin, ready].filter((index) => index >= 0);
				const nextFrame = resume.length > 0 ? Math.min(...resume) : -1;
				if (end >= 0 && (nextFrame < 0 || end < nextFrame)) {
					at = end + SETTLED_END.length;
					dropping = false;
					continue;
				}
				if (nextFrame >= 0) {
					at = nextFrame;
					dropping = false;
					continue;
				}
				const held = partialTail(data, at, [SETTLED_END, FRAME_ORIGIN, FRAME_READY]);
				carry = data.slice(data.length - held);
				break;
			}
			const parts = kept.filter((part) => part.length > 0);
			return parts.length === 0 ? EMPTY : concat(parts);
		},
	};
}
