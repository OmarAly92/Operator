export type MigrationStatus = "pending" | "completed" | "declined" | "failed";

export interface MigrationState {
	status: MigrationStatus;
	lastAttemptAt?: string;
	completedAt?: string;
	report?: { projectsImported: number; projectsSkipped: number };
	error?: string;
}
