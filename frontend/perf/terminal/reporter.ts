type FetchRequest = (input: string, init: RequestInit) => Promise<unknown>;

export function createOrderedReporter<Message>(url: string, fetchRequest: FetchRequest = fetch) {
	let pending = Promise.resolve<unknown>(undefined);
	return (message: Message) => {
		// One failed POST must not poison the chain: a rejection here would skip
		// every later report and stall the run behind a misleading timeout.
		pending = pending.then(() => fetchRequest(url, {
			body: JSON.stringify(message),
			headers: { "content-type": "text/plain;charset=UTF-8" },
			keepalive: true,
			method: "POST",
		})).catch(() => undefined);
		return pending;
	};
}
