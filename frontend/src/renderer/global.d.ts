import type { OperatorBridge } from "../preload";

declare global {
	interface Window {
		operator?: OperatorBridge;
	}

	interface ImportMetaEnv {
		readonly VITE_OPERATOR_POSTHOG_KEY?: string;
		readonly VITE_OPERATOR_POSTHOG_HOST?: string;
	}
}

export {};
