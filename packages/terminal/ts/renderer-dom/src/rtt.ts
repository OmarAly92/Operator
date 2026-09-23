export const RTT_WINDOW = 8;
export const RTT_STALE_MS = 2000;

// wezterm/wezterm-client/src/pane/renderable.rs should_predict
export class RttMeter {
	private samples: number[] = [];
	private sentAt: number | null = null;

	sent(nowMs: number): boolean {
		if (this.sentAt !== null && nowMs - this.sentAt <= RTT_STALE_MS) return false;
		this.sentAt = nowMs;
		return true;
	}

	cancel(): void {
		this.sentAt = null;
	}

	received(nowMs: number): void {
		if (this.sentAt === null) return;
		const elapsed = nowMs - this.sentAt;
		this.sentAt = null;
		if (elapsed > RTT_STALE_MS) return;
		this.samples.push(elapsed);
		if (this.samples.length > RTT_WINDOW) this.samples.shift();
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
