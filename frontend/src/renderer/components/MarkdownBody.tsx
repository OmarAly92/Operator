import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { cn } from "../lib/utils";

export function MarkdownBody({
	body,
	clamped = false,
	testId,
	className,
}: {
	body: string;
	clamped?: boolean;
	testId?: string;
	className?: string;
}) {
	return (
		<div
			className={cn(
				"min-w-0 break-words text-2xs leading-relaxed text-muted-foreground",
				"[&_a]:font-medium [&_a]:text-foreground [&_a]:underline [&_a]:underline-offset-2",
				"[&_code]:rounded [&_code]:bg-muted/55 [&_code]:px-1 [&_code]:py-0.5 [&_code]:font-mono [&_code]:text-foreground",
				"[&_li]:my-0.5 [&_ol]:my-1.5 [&_ol]:list-decimal [&_ol]:pl-4 [&_p]:my-1.5 [&_pre]:my-2",
				"[&_pre]:overflow-x-auto [&_pre]:rounded-md [&_pre]:border [&_pre]:border-border [&_pre]:bg-muted/35 [&_pre]:p-2",
				"[&_pre_code]:bg-transparent [&_pre_code]:p-0 [&_strong]:text-foreground [&_table]:my-2 [&_table]:w-full",
				"[&_table]:border-collapse [&_td]:border [&_td]:border-border [&_td]:px-2 [&_td]:py-1",
				"[&_th]:border [&_th]:border-border [&_th]:px-2 [&_th]:py-1 [&_th]:text-foreground",
				"[&_ul]:my-1.5 [&_ul]:list-disc [&_ul]:pl-4 [&>*:first-child]:mt-0 [&>*:last-child]:mb-0",
				"[&_h1]:mt-4 [&_h1]:text-base [&_h1]:font-semibold [&_h1]:text-foreground",
				"[&_h2]:mt-4 [&_h2]:text-sm [&_h2]:font-semibold [&_h2]:text-foreground",
				"[&_h3]:mt-3 [&_h3]:font-semibold [&_h3]:text-foreground [&_hr]:my-3 [&_hr]:border-border",
				clamped && "line-clamp-4",
				className,
			)}
			data-testid={testId}
		>
			<ReactMarkdown
				components={{
					a: ({ href, children }) => (
						<a href={href} target="_blank" rel="noopener noreferrer">
							{children}
						</a>
					),
				}}
				remarkPlugins={[remarkGfm]}
			>
				{body}
			</ReactMarkdown>
		</div>
	);
}
