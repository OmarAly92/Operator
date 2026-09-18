import { createFileRoute } from "@tanstack/react-router";
import { TicketPage } from "../components/tickets/TicketPage";

type TicketSearch = { file?: string };

export const Route = createFileRoute("/_shell/projects/$projectId_/tickets/$slug")({
	validateSearch: (search: Record<string, unknown>): TicketSearch => ({
		file: typeof search.file === "string" && search.file !== "" ? search.file : undefined,
	}),
	component: TicketRoute,
});

function TicketRoute() {
	const { projectId, slug } = Route.useParams();
	const { file } = Route.useSearch();
	return <TicketPage projectId={projectId} slug={slug} file={file} />;
}
