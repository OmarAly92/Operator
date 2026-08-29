export const REPORT_TIMEOUT_MS = 900000;

export async function installReportChannel(page, timeoutMs = REPORT_TIMEOUT_MS) {
	let resolveResult;
	let rejectResult;
	let timeout;
	let settled = false;
	const result = new Promise((resolve, reject) => {
		resolveResult = resolve;
		rejectResult = reject;
	});
	void result.catch(() => {});

	const cleanup = () => {
		if (timeout !== undefined) {
			clearTimeout(timeout);
			timeout = undefined;
		}
		page.off("crash", onCrash);
		page.off("pageerror", onPageError);
	};
	const settle = (error, value) => {
		if (settled) return;
		settled = true;
		cleanup();
		if (error) rejectResult(error);
		else resolveResult(value);
	};
	const onCrash = () => settle(new Error("benchmark page crashed"));
	const onPageError = (error) => settle(new Error(`benchmark page error: ${error.message}`));

	page.once("crash", onCrash);
	page.once("pageerror", onPageError);
	try {
		await page.exposeFunction("__operatorBenchmarkReport", (value) => {
			if (value && typeof value === "object" && "error" in value) {
				settle(new Error(String(value.error)));
			} else {
				settle(undefined, value);
			}
		});
	} catch (error) {
		cleanup();
		throw error;
	}
	if (!settled) {
		timeout = setTimeout(
			() => settle(new Error(`browser benchmark report timed out after ${timeoutMs} ms`)),
			timeoutMs,
		);
	}
	return { result, dispose: cleanup };
}
