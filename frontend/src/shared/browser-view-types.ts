export type BrowserRect = {
	x: number;
	y: number;
	width: number;
	height: number;
};

export type BrowserNavState = {
	viewId: string;
	url: string;
	title: string;
	canGoBack: boolean;
	canGoForward: boolean;
	isLoading: boolean;
	error?: string;
};

export type BrowserTabState = {
	id: string;
	url: string;
	title: string;
	active: boolean;
	favicon?: string;
};

export type BrowserTabsState = {
	viewId: string;
	activeTabId: string;
	tabs: BrowserTabState[];
	change?: {
		kind: "opened" | "popup" | "selected" | "closed";
		tabId: string;
	};
};

export type BrowserAgentActivityState = {
	viewId: string;
	active: boolean;
	action: string;
	phase?: "started" | "finished";
	commandId?: string;
};

export type BrowserDevToolsPlacement = "right" | "bottom" | "left" | "undocked";

export type BrowserDevToolsState = {
	viewId: string;
	open: boolean;
	activeTabId: string;
	placement?: BrowserDevToolsPlacement;
};

export type BrowserDevToolsInput = {
	viewId: string;
	operation: "open" | "close" | "setPlacement";
	placement?: BrowserDevToolsPlacement;
};
