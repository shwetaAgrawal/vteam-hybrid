---
agent-notes:
  ctx: "implementation gotchas and established patterns"
  deps: [CLAUDE.md]
  state: active
  last: "coordinator@2026-03-12"
---
# Known Patterns and Gotchas

Extracted from CLAUDE.md to reduce context window load. Read this when working on implementation or debugging tasks. Projects populate sections as they discover gotchas.

## Testing Patterns (Tara)

<!-- Tara: add project-specific testing gotchas here as you discover them.
     Examples: mocking strategies that work/fail, flaky test patterns,
     edge cases that keep recurring, test setup quirks. -->

## Code Review Findings (Vik)

<!-- Vik: add recurring code smells, complexity hotspots, and accepted
     trade-offs here. Tracking these avoids redundant flagging across sessions. -->

## Security & Compliance (Pierrot)

<!-- Pierrot: add accepted risks, threat surfaces evaluated, and security
     trade-offs here. Decisions the human explicitly approved should be recorded
     so they aren't re-flagged in future sessions. -->

## Implementation Patterns (Sato)

<!-- Sato: add codebase-specific implementation patterns, performance learnings,
     and quirks here. Examples: which abstractions work well, fragile areas,
     API client behaviors that differ from their types. -->

## Architecture Patterns (Archie)

<!-- Archie: add architectural constraints, integration point knowledge, and
     schema evolution notes here. Patterns that informed past ADRs but aren't
     worth a standalone ADR themselves. -->

## Adapter / Integration Gotchas

- **execa v9 `stdin: 'pipe'` default hangs subprocesses.** execa v9 changed `stdin` from `'inherit'` to `'pipe'`. CLI tools that check stdin connectivity (e.g., `claude -p`, `gemini`) see a connected pipe and wait for EOF, which never comes — the subprocess hangs until timeout. **Detection signal:** subprocess calls work with `--version` or `--help` (which exit immediately) but hang with actual workload flags. **Fix:** always set `stdin: 'ignore'` unless you explicitly need to write to the subprocess's stdin. Audit all execa/child_process calls to explicitly configure all three stdio channels.

- **Health checks that don't exercise the real code path.** A health check like `tool --version` exits immediately without reading stdin, so it succeeds even when the actual call (`tool -p "prompt"`) would hang. **Detection signal:** health check passes but actual tool invocation fails/hangs. **Fix:** health checks should exercise the same flags and stdio configuration as the real invocation, just with minimal input.

## Build and Run

<!-- Add build, bundling, and runtime gotchas here -->

## Process

- **Plans don't replace process (Plan-as-Bypass anti-pattern).** A detailed implementation plan (from plan mode, a prior session, or a human-provided spec) is **input** to the V-Team phases, not a bypass. The plan still needs: GitHub issues (Grace), architecture gate if applicable (Archie + Wei as standalone agents), TDD (Tara → Sato), code review (Vik + Tara + Pierrot), and Done Gate. **Detection signal:** if the coordinator's first tool call is `Read` on a source file (not `docs/code-map.md`, governance docs, or the sprint plan), it's likely in bypass mode. See `2026-02-20-process-violation-plan-bypass.md` for the full retro.

- **Wei must be invoked as a standalone agent.** The coordinator's own analysis of trade-offs is not a substitute for invoking Wei as a standalone agent during architecture debates. If an ADR claims "Wei debate resolved" but no Wei agent was spawned, the gate has not passed.

- **"Invoke the team" means spawn subagents (Solo-Coordinator anti-pattern).** When the human uses language like "invoke the team", "use the team", "have Cam look at this", or names any persona, the coordinator MUST spawn those agents via the Task tool. The coordinator doing the work inline — even if the output is good — violates the explicit human request. **Detection signal:** the human asked for a named persona or "the team" but no Task tool calls with `subagent_type` matching a persona appear in the response. **Fix:** parse the request for persona names or team-level language, then spawn the appropriate agents before doing any work.

- **Use scripts for stable logic, commands for evolving knowledge.** Static scripts are ideal when the rules are well-defined and unlikely to change. But when automation requires understanding things that change externally — evolving formats, shifting best practices, new API conventions — prefer a Claude Code command over a script. Commands bring current understanding (and can web-search) on every run.

- **Proxy mode is conservative, not permissive.** When the human is unavailable and Pat is acting as proxy, Pat defaults to the safer, more reversible option. The guardrails are strict:

  | Pat CAN (proxy) | Pat CANNOT (proxy) |
  |-----------------|-------------------|
  | Prioritize backlog items | Approve or reject ADRs |
  | Accept features against existing criteria | Change project scope |
  | Answer questions covered by product-context.md | Make architectural choices |
  | Defer items to next sprint | Merge to main |
  | Apply conservative defaults | Override Pierrot or Tara vetoes |

  When a question falls outside proxy authority, it blocks until the human returns. All proxy decisions are logged in `.claude/handoff.md` under `## Proxy Decisions (Review Required)`.

- **Product-context is a hypothesis, not ground truth.** `docs/product-context.md` captures Pat's model of the human's product philosophy — it's an educated guess that improves over time. The human can correct it at any time. When the human overrides a product-context-based recommendation, Pat updates the doc and logs the correction in the Correction Log table. Don't treat product-context entries as immutable rules.

- **Phase 1b must precede acceptance criteria writing.** Pat's Human Model Elicitation (kickoff Phase 1b) must complete before Pat writes acceptance criteria (Phase 4). The product context informs what "done" means to this human. Skipping 1b means acceptance criteria are written without understanding the human's quality bar, scope appetite, or non-negotiables.

- **Verify GitHub access before board operations.** Any workflow that touches the project board (sprint-boundary, kickoff, resume, handoff) must verify `gh auth status` and board accessibility before attempting board operations. If `gh` commands fail, STOP and ask the user to fix it — don't proceed and fail mid-workflow. The pre-flight checks are in: sprint-boundary Step 0, kickoff Phase 5 Pre-Flight, resume Step 3, and handoff Step 1. The resume check is especially critical — without it, a full sprint runs board-blind and every status transition is silently skipped.

- **Check devcontainer before implementation.** After planning completes (either via `/plan` or `/kickoff` Phase 5), check whether `.devcontainer/` exists. If not, ask the user if they want one before starting implementation. This prevents environment inconsistency issues during TDD cycles.

- **Agents own their gotchas sections.** The agent-attributed sections at the top of this file (Testing Patterns → Tara, Code Review Findings → Vik, etc.) are written by the named agent at the end of their work, as part of the done gate or handoff. Record project-specific operational knowledge that would save time in a future session — not general programming knowledge, not things already in ADRs or `code-map.md`. Keep entries specific: "mock the gateway at HTTP level, not SDK level, because the SDK swallows retry errors" beats "be careful with mocking." If an entry becomes broadly relevant beyond its section, promote it to an ADR, `code-map.md`, or the template itself.

- **Sprint boundary must end with a clean-tree gate.** Multi-step workflows (sprint boundary, kickoff) involve many file operations — archival moves, artifact creation, code reviews. Commits that run partway through the workflow leave late-written files unstaged. The `/sprint-boundary` Step 8 enforces a terminal `git status --porcelain` check and stages any orphaned changes. If you're writing a similar multi-step workflow, end it with the same pattern: check, stage, commit, re-check.

- **Diagnostic Blindness anti-pattern.** When a testing or debugging gap is identified, the team designs solutions from scratch (install LibreOffice for visual testing, build a custom comparator, add a new dependency) without checking whether a planned backlog item already solves the problem. A "preview" feature planned for sprint 8 is exactly the visual test oracle you need in sprint 3 — but because Tara thinks about test infrastructure and Pat thinks about feature priority in separate loops, neither connects the dots. **Detection signal:** Tara proposes heavyweight test infrastructure for visual/output verification while a rendering, preview, or export feature sits in the backlog. Sato designs a debugging approach that duplicates a planned observability feature. **Fix:** (1) Tara scans the backlog during test design for features that could serve as test oracles or diagnostic tools — see Tara's "Backlog-Aware Test Design" section. (2) Pat applies "dual-duty prioritization" — items that serve both user-facing and internal purposes get a priority boost and are candidates for pull-forward. (3) During sprint planning, the coordinator asks: "Does any backlog item enable better testing or diagnostics for what we've already built?" See `docs/process/team-governance.md` § Sprint Planning Integration.

- **Horizontal Blindness anti-pattern.** Cross-cutting concerns (logging, error UX, config, debug support, README accuracy) fall between vertical work items. No single item owns them, so they degrade silently. **Detection signal:** 3+ sprints in with no logging or debug flags, README quick-start is broken, error messages are inconsistent across modules. **Fix:** run the operational baseline audit (`docs/process/operational-baseline.md`). Done Gate #14 catches per-item regressions; sprint boundary Step 5b catches product-level drift.

- **Green-Bar-Red-Product anti-pattern.** Every Done Gate passes individually, but the product isn't shippable — no observability, broken quick-start, inconsistent errors. The per-item gate verifies each item in isolation; it cannot see product-level properties that emerge from the combination. **Detection signal:** all items pass Done Gate, but a new user can't get the product working from the README, or production failures produce no useful diagnostics. **Fix:** Done Gate #14 provides per-item defense; sprint boundary Step 5b provides product-level defense. Both reference `docs/process/operational-baseline.md`.
