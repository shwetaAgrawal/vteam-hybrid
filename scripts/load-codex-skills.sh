#!/usr/bin/env bash
# agent-notes: { ctx: "install repo-local Codex skills", deps: [".codex/skills/", "AGENTS.md"], state: active, last: "sato@2026-04-05" }

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/load-codex-skills.sh [options]

Install repo-local Codex skills from .codex/skills into the active Codex
skills directory.

Default behavior:
  - Source: <repo>/.codex/skills
  - Destination: ${CODEX_HOME:-$HOME/.codex}/skills
  - Mode: symlink

Options:
  --source PATH        Override the repo-local skills directory.
  --dest PATH          Override the destination Codex skills directory.
  --mode MODE          Install mode: symlink or copy. Default: symlink
  --force              Replace existing destinations.
  --help               Show this help text.

Examples:
  scripts/load-codex-skills.sh
  scripts/load-codex-skills.sh --mode copy
  scripts/load-codex-skills.sh --dest "$HOME/.codex/skills" --force
EOF
}

log() {
  printf '%s\n' "$*"
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

SOURCE_DIR="${REPO_ROOT}/.codex/skills"
DEST_DIR="${CODEX_HOME:-${HOME}/.codex}/skills"
MODE="symlink"
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || fail "--source requires a path"
      SOURCE_DIR="$2"
      shift 2
      ;;
    --dest)
      [[ $# -ge 2 ]] || fail "--dest requires a path"
      DEST_DIR="$2"
      shift 2
      ;;
    --mode)
      [[ $# -ge 2 ]] || fail "--mode requires a value"
      MODE="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ "$MODE" == "symlink" || "$MODE" == "copy" ]] || fail "--mode must be 'symlink' or 'copy'"
[[ -d "$SOURCE_DIR" ]] || fail "source directory not found: $SOURCE_DIR"

mkdir -p "$DEST_DIR"

skill_count=0
installed_count=0
skipped_count=0

for skill_dir in "$SOURCE_DIR"/*; do
  [[ -d "$skill_dir" ]] || continue

  skill_name="$(basename "$skill_dir")"
  skill_file="${skill_dir}/SKILL.md"
  target_path="${DEST_DIR}/${skill_name}"

  if [[ ! -f "$skill_file" ]]; then
    log "Skipping ${skill_name}: missing SKILL.md"
    skipped_count=$((skipped_count + 1))
    continue
  fi

  skill_count=$((skill_count + 1))

  if [[ -e "$target_path" || -L "$target_path" ]]; then
    if [[ "$MODE" == "symlink" && -L "$target_path" ]]; then
      existing_target="$(readlink "$target_path")"
      if [[ "$existing_target" == "$skill_dir" ]]; then
        log "Up to date: ${skill_name}"
        skipped_count=$((skipped_count + 1))
        continue
      fi
    fi

    if [[ "$FORCE" -eq 1 ]]; then
      rm -rf "$target_path"
    else
      log "Skipping ${skill_name}: destination exists (${target_path}). Use --force to replace."
      skipped_count=$((skipped_count + 1))
      continue
    fi
  fi

  if [[ "$MODE" == "symlink" ]]; then
    ln -s "$skill_dir" "$target_path"
    log "Linked ${skill_name} -> ${target_path}"
  else
    cp -R "$skill_dir" "$target_path"
    log "Copied ${skill_name} -> ${target_path}"
  fi

  installed_count=$((installed_count + 1))
done

if [[ "$skill_count" -eq 0 ]]; then
  fail "no skill directories with SKILL.md found in ${SOURCE_DIR}"
fi

log ""
log "Done."
log "  Source: ${SOURCE_DIR}"
log "  Destination: ${DEST_DIR}"
log "  Mode: ${MODE}"
log "  Installed: ${installed_count}"
log "  Skipped: ${skipped_count}"
