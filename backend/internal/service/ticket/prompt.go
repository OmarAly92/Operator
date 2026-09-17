package ticket

import (
	"fmt"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func ticketFolder(slug string) string {
	return domain.TicketsDir + "/" + slug
}

func planningPrompt(t domain.Ticket, extra string) string {
	folder := ticketFolder(t.Slug)
	var b strings.Builder
	fmt.Fprintf(&b, "You are planning ticket `%s` (%s) for this repository.\n\n", t.Slug, t.Title)
	fmt.Fprintf(&b, "The ticket folder is `%s/`, relative to your working directory. It must end up with this layout:\n\n", folder)
	b.WriteString("```\n")
	fmt.Fprintf(&b, "%s/\n", folder)
	b.WriteString("  ticket.md            frontmatter: title, brief, created\n")
	b.WriteString("  spec.md              the design spec\n")
	b.WriteString("  plans/01-<phase>.md  one implementation plan per phase, in dependency order\n")
	b.WriteString("  plans/01-<phase>.kickoff.md  the prompt a fresh session needs to execute that plan\n")
	b.WriteString("  plans/02-<phase>.md\n")
	b.WriteString("  plans/02-<phase>.kickoff.md\n")
	b.WriteString("```\n\n")
	b.WriteString("Every plan file starts with YAML frontmatter containing `title:`. The two-digit numeric prefix is the phase order; Operator reads it to know which phase depends on which. Do not put these documents anywhere else.\n\n")
	b.WriteString("Each kickoff file is the complete prompt for a separate, weaker session that will implement that plan with no other context: which files to read first and in what order, the process to follow, the gates to run, what to report, and when to stop and ask. Operator hands it to the implementing session verbatim after a short header naming the ticket and the paths.\n\n")
	if t.Brief != "" {
		fmt.Fprintf(&b, "Brief: %s\n\n", t.Brief)
	}
	if len(t.Plans) == 0 {
		b.WriteString("Brainstorm the design with the user, then write `spec.md`, then one plan per phase under `plans/`. Use whatever planning workflow you have available.\n")
	} else {
		b.WriteString("The ticket already has documents; revise them with the user rather than starting over. Existing plans:\n")
		for _, p := range t.Plans {
			fmt.Fprintf(&b, "- %s (%s)\n", p.File, p.Title)
		}
	}
	b.WriteString("\nWhen the documents are ready, commit the ticket folder.\n")
	if extra = strings.TrimSpace(extra); extra != "" {
		b.WriteString("\nAdditional instructions:\n" + extra + "\n")
	}
	return b.String()
}

func implementPrompt(t domain.Ticket, plan domain.Plan, kickoff, extra string) string {
	folder := ticketFolder(t.Slug)
	var b strings.Builder
	fmt.Fprintf(&b, "You are implementing one phase of ticket `%s` (%s).\n\n", t.Slug, t.Title)
	if t.Brief != "" {
		fmt.Fprintf(&b, "Brief: %s\n\n", t.Brief)
	}
	b.WriteString("Read these first, relative to your working directory:\n")
	fmt.Fprintf(&b, "- `%s/spec.md` (the design spec)\n", folder)
	fmt.Fprintf(&b, "- `%s/%s` (the plan for this phase: %s)\n", folder, plan.File, plan.Title)
	var earlier []string
	for _, p := range t.Plans {
		if p.File == plan.File {
			break
		}
		earlier = append(earlier, fmt.Sprintf("- %s (%s)", p.File, phaseState(p.Status)))
	}
	if len(earlier) > 0 {
		b.WriteString("\nEarlier phases of this ticket:\n" + strings.Join(earlier, "\n") + "\n")
	}
	if kickoff = strings.TrimSpace(kickoff); kickoff != "" {
		b.WriteString("\n" + kickoff + "\n")
	} else {
		b.WriteString("\nImplement only this phase. Open a pull request when the plan's final verification passes.\n")
	}
	if extra = strings.TrimSpace(extra); extra != "" {
		b.WriteString("\nAdditional instructions:\n" + extra + "\n")
	}
	return b.String()
}

func reviewPrompt(t domain.Ticket, plan domain.Plan, branch, worktree, mergeReadyCurl, extra string) string {
	folder := ticketFolder(t.Slug)
	var b strings.Builder
	fmt.Fprintf(&b, "Review the implementation of `%s` (%s) for ticket `%s` (%s).\n\n", plan.File, plan.Title, t.Slug, t.Title)
	b.WriteString("Read first, relative to the project root:\n")
	fmt.Fprintf(&b, "- `%s/spec.md`\n", folder)
	fmt.Fprintf(&b, "- `%s/%s`\n", folder, plan.File)
	fmt.Fprintf(&b, "\nThe implementing session worked on branch `%s`", branch)
	if worktree != "" {
		fmt.Fprintf(&b, " in the worktree `%s`", worktree)
	}
	b.WriteString(".\n\nReview the whole branch against the spec and the plan, not only the diff summary: read every changed file, run the gates the plan names, and verify the behaviour in the real app or daemon, not just in tests. Fix what is wrong on that branch and commit the fixes there. Do not merge.\n\n")
	b.WriteString("When the branch is ready to merge, report it to Operator with one line describing what was verified:\n\n```\n" + mergeReadyCurl + "\n```\n\nThen wait. The user confirms the merge from the board and you will receive the go-ahead here.\n")
	if extra = strings.TrimSpace(extra); extra != "" {
		b.WriteString("\nAdditional instructions:\n" + extra + "\n")
	}
	return b.String()
}

func mergeApprovedPrompt(t domain.Ticket, plan domain.Plan, branch, defaultBranch string) string {
	return fmt.Sprintf("Approved: merge `%s` (%s, ticket `%s`) into `%s` now, using the pull request if one is open, then report the merge commit and anything the next phase should know.\n", branch, plan.File, t.Slug, defaultBranch)
}

func phaseState(s domain.PlanStatus) string {
	switch s {
	case domain.PlanStatusMerged, domain.PlanStatusDone:
		return "merged"
	case domain.PlanStatusTodo, domain.PlanStatusTerminated:
		return "not started"
	default:
		return "in progress"
	}
}
