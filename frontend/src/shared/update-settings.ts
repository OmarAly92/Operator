export interface FeaturePin {
	pr: number;
}

export interface UpdateSettings {
	enabled: boolean;
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
