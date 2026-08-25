// Ambient typings for the slice of the WebdriverIO runtime this suite uses.
// The pinned @wdio packages inject these globals at runtime; declaring them here
// keeps the suite typecheckable without depending on transitive type-entry
// resolution for the whole WebDriver API surface.

declare function $(selector: string): Promise<WDIOElement>;

interface WDIOElement {
	isExisting: () => Promise<boolean>;
	getText: () => Promise<string>;
	click: () => Promise<void>;
}

declare const browser: {
	execute: (script: string) => Promise<any>;
	takeScreenshot: () => Promise<string>;
};
