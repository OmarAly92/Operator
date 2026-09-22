export const RTT_WINDOW = 8;

// wezterm/wezterm-client/src/pane/renderable.rs should_predict
export class RttMeter {
	private samples: number[] = [];
	private sentAt: number | null = null;

	sent(nowMs: number): void {
		if (this.sentAt === null) this.sentAt = nowMs;
	}

	received(nowMs: number): void {
		if (this.sentAt === null) return;
		this.samples.push(nowMs - this.sentAt);
		if (this.samples.length > RTT_WINDOW) this.samples.shift();
		this.sentAt = null;
	}

	median(): number | null {
		if (this.samples.length === 0) return null;
		const sorted = [...this.samples].sort((a, b) => a - b);
		return sorted[Math.floor(sorted.length / 2)]!;
	}

	shouldPredict(thresholdMs: number): boolean {
		const median = this.median();
		return median !== null && median >= thresholdMs;
	}
}
