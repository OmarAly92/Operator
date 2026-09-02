export const HIDDEN_MEASURE_ID = "terminal-m-measure";

export function ensureMeasureHost(): HTMLElement {
	const existing = document.getElementById("terminal-measure-host");
	if (existing) {
		return existing;
	}
	const host = document.createElement("div");
	host.id = "terminal-measure-host";
	host.style.position = "absolute";
	host.style.visibility = "hidden";
	host.style.pointerEvents = "none";
	host.style.left = "-9999px";
	host.style.top = "0";
	const node = document.createElement("span");
	node.id = HIDDEN_MEASURE_ID;
	node.textContent = "M";
	host.append(node);
	document.body.append(host);
	return host;
}

export function listenScroll(target: EventTarget, listener: () => void): () => void {
	target.addEventListener("scroll", listener, { passive: true });
	return () => target.removeEventListener("scroll", listener);
}
