import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const { getApiBaseUrlMock, hasTrustedApiBaseUrlMock, subscribeApiBaseUrlMock, unsubscribeBaseUrlMock } = vi.hoisted(
	() => ({
		getApiBaseUrlMock: vi.fn(() => "http://127.0.0.1:3001"),
		hasTrustedApiBaseUrlMock: vi.fn(() => true),
		subscribeApiBaseUrlMock: vi.fn(),
		unsubscribeBaseUrlMock: vi.fn(),
	}),
);

vi.mock("./api-client", () => ({
	getApiBaseUrl: getApiBaseUrlMock,
	hasTrustedApiBaseUrl: hasTrustedApiBaseUrlMock,
	subscribeApiBaseUrl: subscribeApiBaseUrlMock,
}));

import { subscribeTicketChanges } from "./ticket-events";

class EventSourceStub {
	static instances: EventSourceStub[] = [];
	url: string;
	closed = false;
	readyState = 0;
	onopen: (() => void) | null = null;
	onerror: (() => void) | null = null;
	listeners = new Map<string, Set<() => void>>();

	constructor(url: string) {
		this.url = url;
		EventSourceStub.instances.push(this);
	}

	addEventListener(type: string, listener: () => void) {
		const listeners = this.listeners.get(type) ?? new Set();
		listeners.add(listener);
		this.listeners.set(type, listeners);
	}

	dispatch(type: string) {
		for (const listener of this.listeners.get(type) ?? []) listener();
	}

	close() {
		this.closed = true;
		this.readyState = 2;
	}
}

function fakeQueryClient() {
	return { invalidateQueries: vi.fn() } as unknown as Parameters<typeof subscribeTicketChanges>[1];
}

beforeEach(() => {
	EventSourceStub.instances = [];
	getApiBaseUrlMock.mockReset().mockReturnValue("http://127.0.0.1:3001");
	hasTrustedApiBaseUrlMock.mockReset().mockReturnValue(true);
	subscribeApiBaseUrlMock.mockReset().mockReturnValue(unsubscribeBaseUrlMock);
	unsubscribeBaseUrlMock.mockReset();
	(globalThis as unknown as { EventSource: unknown }).EventSource = EventSourceStub;
	vi.useFakeTimers();
});

afterEach(() => {
	vi.useRealTimers();
});

describe("subscribeTicketChanges", () => {
	it("opens the project's ticket stream and invalidates the ticket queries on change", () => {
		const queryClient = fakeQueryClient();
		const unsubscribe = subscribeTicketChanges("my app", queryClient);
		expect(EventSourceStub.instances).toHaveLength(1);
		expect(EventSourceStub.instances[0].url).toBe("http://127.0.0.1:3001/api/v1/projects/my%20app/tickets/events");

		EventSourceStub.instances[0].dispatch("tickets_changed");
		vi.advanceTimersByTime(200);
		expect(queryClient.invalidateQueries).toHaveBeenCalledWith({ queryKey: ["tickets", "my app"] });

		unsubscribe();
		expect(EventSourceStub.instances[0].closed).toBe(true);
		expect(unsubscribeBaseUrlMock).toHaveBeenCalledTimes(1);
	});

	it("shares one stream per project across subscribers", () => {
		const queryClient = fakeQueryClient();
		const first = subscribeTicketChanges("p1", queryClient);
		const second = subscribeTicketChanges("p1", queryClient);
		expect(EventSourceStub.instances).toHaveLength(1);
		first();
		expect(EventSourceStub.instances[0].closed).toBe(false);
		second();
		expect(EventSourceStub.instances[0].closed).toBe(true);
	});

	it("reconnects after the stream closes", () => {
		const queryClient = fakeQueryClient();
		const unsubscribe = subscribeTicketChanges("p1", queryClient);
		const source = EventSourceStub.instances[0];
		source.readyState = 2;
		source.onerror?.();
		vi.advanceTimersByTime(5_000);
		expect(EventSourceStub.instances).toHaveLength(2);
		unsubscribe();
	});

	it("does nothing while the daemon base URL is untrusted", () => {
		hasTrustedApiBaseUrlMock.mockReturnValue(false);
		const unsubscribe = subscribeTicketChanges("p1", fakeQueryClient());
		expect(EventSourceStub.instances).toHaveLength(0);
		unsubscribe();
	});
});
