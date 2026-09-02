import { useLayoutEffect, useRef } from "react";
import type { AttachableTerminal } from "../hooks/useTerminalSession";

export type TerminalAttachmentProps = {
	columns?: number;
	rows?: number;
	onReady?: (terminal: AttachableTerminal) => void;
};

export function TerminalAttachment({ columns = 80, rows = 24, onReady }: TerminalAttachmentProps) {
	const onReadyRef = useRef(onReady);
	onReadyRef.current = onReady;
	useLayoutEffect(() => {
		const disposable = { dispose: () => undefined };
		onReadyRef.current?.({
			cols: columns,
			rows,
			write: (_data, done) => done?.(),
			writeln: () => undefined,
			showLatestOutput: () => undefined,
			prepareForActivation: () => Promise.resolve(),
			onUserInput: () => disposable,
			onResize: () => disposable,
		});
	}, [columns, rows]);
	return null;
}
