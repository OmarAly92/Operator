import { apiClient, apiErrorMessage } from "./api-client";

export const mobileStatusQueryKey = ["mobile-status"] as const;

export interface MobileTunnelStatus {
	state: string;
	provider: string;
	url: string;
	error: string;
	since?: string;
	restarts: number;
	needsAuthtoken: boolean;
	hasAuthtoken: boolean;
}

export interface MobileStatus {
	enabled: boolean;
	host: string;
	port: number;
	password: string;
	warning: string;
	tunnel?: MobileTunnelStatus;
}

// pairingPayload is the QR code contents scanned by the mobile app to connect
// to the desktop's LAN bridge. It includes the password so a single scan
// autofills everything and connects with no typing. The bridge is a trusted-
// home-network tool over plaintext HTTP, so a QR that grants access is an
// acceptable trade-off; regenerating the password invalidates any old QR.
export function pairingPayload(host: string, port: number, password: string): string {
	return JSON.stringify({ v: 1, host, port, password });
}

export function pairingPayloadV2(url: string, password: string): string {
	return JSON.stringify({ v: 2, url, password });
}

const inFlightTunnelStates = new Set(["downloading", "starting", "reconnecting"]);

export function isTunnelExposed(state: string | undefined): boolean {
	return state === "live" || (state !== undefined && inFlightTunnelStates.has(state));
}

export function tunnelRefetchInterval(state: string | undefined): number | false {
	if (state !== undefined && inFlightTunnelStates.has(state)) return 1000;
	if (state === "live") return 5000;
	return false;
}

export function tunnelIndicatorRefetchInterval(state: string | undefined): number {
	return tunnelRefetchInterval(state) || 15000;
}

export async function fetchMobileStatus(): Promise<MobileStatus> {
	const { data, error } = await apiClient.GET("/api/v1/mobile/status");
	if (error || !data) throw new Error(apiErrorMessage(error));
	return data;
}
