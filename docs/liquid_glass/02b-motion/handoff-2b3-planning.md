You are the main session for project 2B.3 of the ios_liquid_glass Flutter package (packages/mobile/packages/ios_liquid_glass). Your job is to get the 2B.3 implementation plan written, independently reviewed and approved by the user, and then hand it to a fresh execution session. You orchestrate subagents and keep your own context small. Everything you need is on disk; assume you remember nothing from earlier sessions.

Read first, in order:
1. docs/liquid_glass/ROADMAP.md, the whole file:
   - §5 is the working rules;
   - §9 step 1 is your task and its carry-ins;
   - read every gotcha, especially 35 and 43 onwards.
2. docs/liquid_glass/02b-motion/spec.md, the approved spec, which is binding:
   - 2B.3's scope is in §4;
   - the parts are L4 (glow and stretch measures, built first), N3 (drags), N4 (neighbours), N6 (Reduce Motion for interactive glass and drags), M7 (press), M8 (Reduce Motion everywhere), M10 (frame cost) and M9's README;
   - the Done list is in §8, "2B.3 is done when";
   - the required prototypes are in §12.
3. docs/liquid_glass/02b-motion/brainstorm.md: every decision the user has made. Note especially section 4 as revised to (a2): stretch and glow spreading are built only where native shows them, and copied exactly.
4. docs/liquid_glass/02b-motion/spike-interactive.md: the native press facts.
   - The press is a uniform scale whose amount falls with size: about +17.5 pt of width for glass up to about 60 pt tall, and about 1100 / height above that. Measure it on `photo`, because gotcha 35's blind band costs about 2 pt on stripes.
   - The glow comes first and the growth second.
   - On release, the glow drops to nothing in one frame.
   - A slow drag gives no stretch.
   - A neighbour 10 pt away gets no glow.
5. results-2b1.md, todo-2b1.md, results-2b2.md and todo-2b2.md: where 2B.1 and 2B.2 ended, and what they carry into 2B.3.
6. As exemplars and lessons:
   - the headers and rulings of plan-2b2.md and plan-2b1.md (do not read them whole);
   - plan-2b2-review.md, review-2b2-code.md, review-2b2-audit.md and rereview-2b2-fixwave1.md.

Goal: ios_liquid_glass becomes identical to native iOS 27 Liquid Glass for any Flutter app. The user wants perfection, measured against native in the glass lab and never judged by eye. 2B.3 finishes project 2B.

**Keep usage under control.** The user requires this. The 2B.2 plan writer used about 40% of the weekly limit in one day. So:
- Prototype only what the plan cannot be written without.
- Bulk recordings (noise floors, full native reference sets) become execution tasks, not prototype work.
- Use Opus only for analysis, plan writing and reviews. Use `sonnet` subagents for mechanical work: recordings, simulator driving, gates, replays.
- Before any long subagent run, tell the user what it will do and roughly how long it will take.

The process the user requires:
1. **Plan writer (subagent).** Write a brief file in your scratchpad, then dispatch the plan writer.
   - It works in a throwaway worktree: `git -C /Users/omaraly/development/AI/Operator worktree add /Users/omaraly/development/AI/Operator-2b3-proto -b proto/2b3 development`.
   - It proves the risky pieces on the iOS 27 simulator. Likely ones:
     - the L4 glow and stretch measures reproducing the spike's numbers;
     - the press scale law against N2;
     - the container-level glow layer;
     - pointer listening that never enters the gesture arena;
     - the A9 re-raster cost while glass slides.
   - It embeds the tested code verbatim.
   - Every departure from the spec is a numbered ruling with evidence.
   - It follows the superpowers:writing-plans structure: Global Constraints, Review Focus, and reviewable test-first tasks.
   - It replays the plan task by task onto a fresh export of development, matching the prototype file for file.
   - It commits on proto/2b3 only.
2. **Independent plan review (another subagent).** It re-runs the gates, diffs the embedded code against the prototype, recomputes every claimed number, and hunts for silent spec departures, unsound measurement and bugs. It writes numbered findings, each with a severity.
3. **Fix rounds.** Resume the plan writer with your ruling on each finding, then run a scoped re-review. Repeat until the verdict is "ready to execute: yes". Bring the user only the decisions that are truly theirs.
4. **Hand over.** Copy the plan, its review record and its evidence onto development (docs only). Write docs/liquid_glass/02b-motion/handoff-2b3.md for the execution session, modelled on handoff-2b2.md. Give the user the one-line prompt to paste into a fresh local session.
5. **After execution,** the user pastes the executor's report back to you.
   - Run an independent code review and an independent measurement audit, both as subagents, in parallel.
   - Then run a fix wave through subagents, with a scoped re-review or re-audit after each round.
   - Merge only when the user says. Then re-run the gates on the merged tree.
   - Push only when the user says.
   - Archive the recordings to /Users/omaraly/development/AI/glass-lab-runs/2b3/, as 2B.1 and 2B.2 were, and delete only with the user's approval.

How to talk to the user:
- Plain words and short messages.
- One decision at a time, as lettered options with your recommendation first. The user usually answers with a letter.
- Say what you are doing while subagents run.

Recordings:
- 2B.1's are archived at /Users/omaraly/development/AI/glass-lab-runs/2b1/ and 2B.2's at .../2b2/.
- To use them, copy what a worktree needs into its own packages/mobile/build/glass_lab/.
- Never record into the archive and never delete from it.

Hard rules, for you and every subagent:
- **Simulator.**
  - Use only the iOS 27 simulator "iPhone 17 Pro (iOS 27)", UDID 708879DD-8B2A-4547-863F-F49EE1474D8B. Name the UDID in every simctl command, never `booted`.
  - Reboot it before recording native references, and keep it exclusive while recording (gotcha 49).
  - Never touch the iOS 26.5 simulator (94D0C207-A90B-4806-BBAB-8AF9B3F16329).
  - Simulator prompts get only "Don't Allow" or "Not Now". Never pair Operator and never enter a password.
- **Builds.** Build lab apps only through tool/glass_lab/harness/lab.py build. A plain `flutter build ios` fails under Xcode 27.
- **Code.** No code comments in any code. Never run dart format on whole files. No downloads, no pip install, no new dependencies.
- **Git.**
  - Every commit message ends with: Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  - Never stage frontend/package-lock.json. Never git stash.
  - The shared checkout /Users/omaraly/development/AI/Operator is for docs, merges and pushes only. Another session may have uncommitted frontend edits there; never touch them.
- **Measurement.** Never loosen a limit or a measure. Fitted values come only from tools.
- **Disk.** Check free disk before any recording. Stop if it falls under 40 GB. Delete nothing without the user's explicit approval.
- **Where sessions run.** Executing sessions run locally on this Mac, never in the cloud.
