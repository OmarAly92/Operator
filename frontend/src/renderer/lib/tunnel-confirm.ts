export const TUNNEL_CONFIRM_STORAGE_KEY = "opr.mobile.tunnelConfirmed";

export function tunnelAlreadyConfirmed(): boolean {
	try {
		return window.localStorage.getItem(TUNNEL_CONFIRM_STORAGE_KEY) === "1";
	} catch {
		return false;
	}
}

export function rememberTunnelConfirmed(): void {
	try {
		window.localStorage.setItem(TUNNEL_CONFIRM_STORAGE_KEY, "1");
	} catch {
		return;
	}
}
