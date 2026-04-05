#!/usr/bin/env bash
# agent-notes: { ctx: "generate repo .codex from .claude", deps: [".claude/commands/", ".claude/agents/", ".codex/skills/", ".codex/agents/"], state: active, last: "sato@2026-04-05" }

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/sync-codex-skills.sh

Rebuild repo-local Codex assets from Claude source files:
  - Generates .codex/skills/<skill>/SKILL.md from .claude/commands/*.md
  - Symlinks .codex/agents/*.md to .claude/agents/*.md

This script treats .claude as the single source of truth.
EOF
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
  /*) ;;
  *) SCRIPT_PATH="${PWD}/${SCRIPT_PATH}" ;;
esac
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CLAUDE_COMMANDS_DIR="${REPO_ROOT}/.claude/commands"
CLAUDE_AGENTS_DIR="${REPO_ROOT}/.claude/agents"
CODEX_ROOT_DIR="${REPO_ROOT}/.codex"
CODEX_SKILLS_DIR="${CODEX_ROOT_DIR}/skills"
CODEX_AGENTS_DIR="${CODEX_ROOT_DIR}/agents"

command_description() {
  case "$1" in
    quickstart)
      printf '%s' 'Use when the user wants a fast vteam-hybrid onboarding flow that captures enough product context to start work quickly.'
      ;;
    kickoff)
      printf '%s' 'Use when the user wants the full vteam-hybrid discovery workflow, including product context, design exploration, and phased setup.'
      ;;
    plan)
      printf '%s' 'Use when the user wants an implementation plan using the local vteam-hybrid workflow, including acceptance criteria and architecture-gate scanning.'
      ;;
    tdd)
      printf '%s' 'Use when the user wants strict TDD using the local vteam-hybrid workflow, especially Tara-first tests followed by implementation.'
      ;;
    code-review)
      printf '%s' 'Use when the user wants a vteam-hybrid code review across maintainability, test quality, security, and architectural-conformance lenses.'
      ;;
    review)
      printf '%s' 'Use when the user wants a guided human-facing review or walkthrough session using the local vteam-hybrid methodology.'
      ;;
    adr)
      printf '%s' 'Use when the user wants to create or refine an architecture decision record using the local vteam-hybrid workflow.'
      ;;
    design)
      printf '%s' 'Use when the user wants design exploration, sacrificial concepts, or accessibility-oriented product thinking from the local vteam-hybrid workflow.'
      ;;
    handoff)
      printf '%s' 'Use when the user wants to capture session state for a clean future resume using the local vteam-hybrid workflow.'
      ;;
    resume)
      printf '%s' 'Use when the user wants to resume work from a prior handoff using the local vteam-hybrid workflow.'
      ;;
    sprint-boundary)
      printf '%s' 'Use when the user wants to run the local vteam-hybrid sprint-boundary workflow, including retro, backlog sweep, and next-sprint setup.'
      ;;
    *)
      printf '%s' "Use when the user wants the local vteam-hybrid '$1' workflow adapted from the repo's Claude command."
      ;;
  esac
}

command_prompt_hint() {
  case "$1" in
    code-review)
      printf '%s' 'vteam-review'
      ;;
    *)
      printf '%s' "vteam-$1"
      ;;
  esac
}

read_first_block() {
  cat <<EOF
- ${REPO_ROOT}/.claude/commands/$1.md
- ${REPO_ROOT}/docs/methodology/personas.md
- ${REPO_ROOT}/docs/process/team-governance.md
- ${REPO_ROOT}/AGENTS.md
EOF
}

generate_skill() {
  local command_name="$1"
  local skill_name="vteam-${command_name}"
  local skill_dir="${CODEX_SKILLS_DIR}/${skill_name}"
  local skill_file="${skill_dir}/SKILL.md"
  local description
  description="$(command_description "$command_name")"

  mkdir -p "$skill_dir"

  cat > "$skill_file" <<EOF
---
name: ${skill_name}
description: ${description}
---

# ${skill_name}

Generated from \`.claude/commands/${command_name}.md\`. Treat the Claude command as the source of truth and this skill as the Codex adapter.

## Read first

$(read_first_block "$command_name")

## What this skill does

- Adapts the local vteam-hybrid \`${command_name}\` workflow into Codex behavior.
- Uses the repo's Claude command as the workflow playbook instead of duplicating process logic here.
- Keeps persona guidance in the source docs and agent briefs rather than forking a second maintained copy.

## Practical rules

- Follow \`${REPO_ROOT}/.claude/commands/${command_name}.md\` as the primary workflow reference.
- Treat \`${REPO_ROOT}/.claude/agents/*.md\` as persona briefs and decision aids, not as auto-executable Codex agents.
- Spawn real Codex subagents only when the user explicitly asks for persona/team involvement or when delegation is clearly warranted by the current instructions.
- Prefer the smallest useful slice of the methodology for the current request.
- If this workflow implies coding, still obey Codex's actual system and developer instructions first.

## Source command excerpt

The source command begins with:

\`\`\`md
$(sed -n '1,12p' "${CLAUDE_COMMANDS_DIR}/${command_name}.md")
\`\`\`
EOF
}

sync_agents() {
  mkdir -p "$CODEX_AGENTS_DIR"
  find "$CODEX_AGENTS_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

  local agent_file target_path
  for agent_file in "$CLAUDE_AGENTS_DIR"/*.md; do
    [[ -f "$agent_file" ]] || continue
    target_path="${CODEX_AGENTS_DIR}/$(basename "$agent_file")"
    ln -s "../../.claude/agents/$(basename "$agent_file")" "$target_path"
  done
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  [[ -d "$CLAUDE_COMMANDS_DIR" ]] || fail "missing commands directory: $CLAUDE_COMMANDS_DIR"
  [[ -d "$CLAUDE_AGENTS_DIR" ]] || fail "missing agents directory: $CLAUDE_AGENTS_DIR"

  mkdir -p "$CODEX_SKILLS_DIR"
  find "$CODEX_SKILLS_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

  local command_file command_name command_count=0
  for command_file in "$CLAUDE_COMMANDS_DIR"/*.md; do
    [[ -f "$command_file" ]] || continue
    command_name="$(basename "$command_file" .md)"
    generate_skill "$command_name"
    command_count=$((command_count + 1))
  done

  [[ "$command_count" -gt 0 ]] || fail "no command files found in $CLAUDE_COMMANDS_DIR"

  sync_agents

  printf 'Synced %s Codex skills into %s\n' "$command_count" "$CODEX_SKILLS_DIR"
  printf 'Linked Codex agents into %s\n' "$CODEX_AGENTS_DIR"
}

main "$@"
