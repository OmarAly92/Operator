export type UpdateChannel = "latest" | "nightly";

export interface FeaturePin {
	pr: number;
}

export interface UpdateSettings {
	enabled: boolean;
	channel: UpdateChannel;
	nightlyAck: boolean;
	feature: FeaturePin | null;
}

export type UpdateState =
	| "idle"
	| "checking"
	| "available"
	| "not-available"
	| "downloading"
	| "downloaded"
	| "error"
	| "unsupported";

export interface UpdateStatus {
	state: UpdateState;
	version?: string;
	percent?: number;
	message?: string;
	requestId?: string;
	stagedAt?: number;
	escalated?: boolean;
}
