export const dynamic = "force-static";

export async function GET() {
	return Response.json({
		$schema: "https://schemas.agentskills.io/discovery/0.2.0/schema.json",
		repository: "https://github.com/OmarAly92/operator",
		skills: [],
	});
}
