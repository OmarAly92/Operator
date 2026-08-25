import { useCallback, useEffect, useRef, useState } from "react";
import type { ExternalPreviewOpenInput } from "../../shared/operator-bridge";
import { operatorBridge } from "../lib/bridge";
import { isAllowedPreviewUrl } from "../lib/preview-url";
import { postPreviewOpenedAck } from "../lib/tauri-bridge";

export type UseExternalPreviewOptions = {
	sessionId?: string;
	previewUrl?: string;
	previewRevision?: number;
	previewOpenedRevision?: number;
	terminated?: boolean;
};

export type ExternalPreviewModel = {
	error: string;
	retry: () => void;
	reopen: (target: string) => Promise<void>;
};

type ConsumedTrigger = { revision: number | null; target: string };

const OPENER_FAILURE_SUFFIX = "could not be opened in your default browser.";
const INVALID_TARGET_MESSAGE = "Only HTTP(S) URLs can be opened as a preview.";

function previewTarget(previewUrl?: string): string {
	return previewUrl?.trim() ?? "";
}

export function useExternalPreview({
	sessionId,
	previewUrl,
	previewRevision,
	previewOpenedRevision,
	terminated,
}: UseExternalPreviewOptions): ExternalPreviewModel {
	const [error, setError] = useState("");
	const consumedRef = useRef<Map<string, ConsumedTrigger>>(new Map());
	const pendingRef = useRef<ExternalPreviewOpenInput | null>(null);
	const generationRef = useRef(0);

	useEffect(() => {
		generationRef.current += 1;
		pendingRef.current = null;
		setError("");
	}, [sessionId, terminated]);

	useEffect(() => {
		if (!sessionId) return;
		if (terminated) {
			consumedRef.current.delete(sessionId);
			pendingRef.current = null;
			return;
		}
		const target = previewTarget(previewUrl);
		const revision = typeof previewRevision === "number" ? previewRevision : null;
		const previous = consumedRef.current.get(sessionId);
		if (previous?.revision === revision && previous.target === target) return;
		if (target === "") {
			consumedRef.current.set(sessionId, { revision, target });
			return;
		}
		const openedFloor =
			typeof previewOpenedRevision === "number"
				? previewOpenedRevision
				: previous?.revision != null && previous.revision > 0
					? previous.revision
					: 0;
		if (revision !== null && revision <= openedFloor) {
			consumedRef.current.set(sessionId, { revision, target });
			return;
		}
		if (!isAllowedPreviewUrl(target)) {
			consumedRef.current.set(sessionId, { revision, target });
			return;
		}
		consumedRef.current.set(sessionId, { revision, target });
		const input: ExternalPreviewOpenInput = { sessionId, url: target, revision: revision ?? 0 };
		pendingRef.current = input;
		const generation = ++generationRef.current;
		void openExternally(input)
			.then(() => {
				if (generation !== generationRef.current) return;
				pendingRef.current = null;
				setError((current) => (current ? "" : current));
			})
			.catch(() => {
				if (generation !== generationRef.current) return;
				setError(`${input.url} ${OPENER_FAILURE_SUFFIX}`);
			});
	}, [sessionId, previewOpenedRevision, previewRevision, previewUrl, terminated]);

	const retry = useCallback(() => {
		const input = pendingRef.current;
		if (!input) {
			setError("");
			return;
		}
		const generation = ++generationRef.current;
		void openExternally(input)
			.then(() => {
				if (generation !== generationRef.current) return;
				pendingRef.current = null;
				setError("");
			})
			.catch(() => {
				if (generation !== generationRef.current) return;
				setError(`${input.url} ${OPENER_FAILURE_SUFFIX}`);
			});
	}, []);

	const reopen = useCallback(
		async (target: string) => {
			const trimmed = target.trim();
			if (!sessionId || !isAllowedPreviewUrl(trimmed)) {
				setError(INVALID_TARGET_MESSAGE);
				return;
			}
			try {
				await operatorBridge.app.openExternal(trimmed);
				setError((current) => (current ? "" : current));
			} catch {
				setError(`${trimmed} ${OPENER_FAILURE_SUFFIX}`);
			}
		},
		[sessionId],
	);

	return { error, retry, reopen };
}

async function openExternally(input: ExternalPreviewOpenInput): Promise<void> {
	const nativePreview = operatorBridge.preview;
	if (nativePreview) {
		await nativePreview.openExternalPreview(input);
		return;
	}
	await operatorBridge.app.openExternal(input.url);
	await postPreviewOpenedAck(input);
}
