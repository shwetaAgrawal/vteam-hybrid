#!/usr/bin/env bash
# agent-notes: { ctx: "activate repo-local Codex skill overlay", deps: [".codex/skills/", "scripts/sync-codex-skills.sh", "scripts/load-codex-skills.sh"], state: active, last: "sato@2026-04-05" }

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/codex-skills-env.sh activate [--source PATH] [--dest PATH] [--prompt LABEL] [--no-sync]
  scripts/codex-skills-env.sh deactivate

This script is designed to be evaluated by your shell so it can define a
deactivation function and restore your prompt, similar to a Python virtualenv.

Examples:
  eval "$(scripts/codex-skills-env.sh activate)"
  eval "$(scripts/codex-skills-env.sh activate --prompt repo-skills)"
  deactivate_codex_skills

Behavior:
  - Activating first runs scripts/sync-codex-skills.sh by default so .codex
    is regenerated from .claude before the overlay is applied.
  - Activating symlinks repo-local skills from .codex/skills into the active
    Codex skills directory.
  - If a destination skill already exists, it is moved into a temporary backup
    area and restored on deactivation.
  - Deactivating removes the overlay and restores the previous destination
    state.
EOF
}

log() {
  printf '%s\n' "$*" >&2
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

shell_quote() {
  printf '%q' "$1"
}

SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
  /*) ;;
  *) SCRIPT_PATH="${PWD}/${SCRIPT_PATH}" ;;
esac
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename "$SCRIPT_PATH")"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

activate() {
  local source_dir="${REPO_ROOT}/.codex/skills"
  local dest_dir="${CODEX_HOME:-${HOME}/.codex}/skills"
  local prompt_label="codex-skills"
  local sync_first=1

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --source)
        [[ $# -ge 2 ]] || fail "--source requires a path"
        source_dir="$2"
        shift 2
        ;;
      --dest)
        [[ $# -ge 2 ]] || fail "--dest requires a path"
        dest_dir="$2"
        shift 2
        ;;
      --prompt)
        [[ $# -ge 2 ]] || fail "--prompt requires a value"
        prompt_label="$2"
        shift 2
        ;;
      --no-sync)
        sync_first=0
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        fail "unknown activate argument: $1"
        ;;
    esac
  done

  if [[ "$sync_first" -eq 1 ]]; then
    "${REPO_ROOT}/scripts/sync-codex-skills.sh" >/dev/null
  fi

  [[ -d "$source_dir" ]] || fail "source directory not found: $source_dir"

  mkdir -p "$dest_dir"

  local state_dir
  state_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-skills-activation.XXXXXX")"
  local backup_dir="${state_dir}/backups"
  local manifest_path="${state_dir}/manifest.tsv"
  mkdir -p "$backup_dir"
  : > "$manifest_path"

  local installed_count=0
  local replaced_count=0
  local skipped_count=0
  local found_count=0

  local skill_dir skill_name skill_file target_path backup_path existing_target
  for skill_dir in "$source_dir"/*; do
    [[ -d "$skill_dir" ]] || continue

    skill_name="$(basename "$skill_dir")"
    skill_file="${skill_dir}/SKILL.md"
    target_path="${dest_dir}/${skill_name}"
    backup_path="${backup_dir}/${skill_name}"

    if [[ ! -f "$skill_file" ]]; then
      log "Skipping ${skill_name}: missing SKILL.md"
      skipped_count=$((skipped_count + 1))
      continue
    fi

    found_count=$((found_count + 1))

    if [[ -L "$target_path" ]]; then
      existing_target="$(readlink "$target_path")"
      if [[ "$existing_target" == "$skill_dir" ]]; then
        printf 'same\t%s\t%s\t%s\n' "$skill_name" "$target_path" "-" >> "$manifest_path"
        skipped_count=$((skipped_count + 1))
        continue
      fi
    fi

    if [[ -e "$target_path" || -L "$target_path" ]]; then
      mv "$target_path" "$backup_path"
      printf 'restore\t%s\t%s\t%s\n' "$skill_name" "$target_path" "$backup_path" >> "$manifest_path"
      replaced_count=$((replaced_count + 1))
    else
      printf 'remove\t%s\t%s\t%s\n' "$skill_name" "$target_path" "-" >> "$manifest_path"
    fi

    ln -s "$skill_dir" "$target_path"
    installed_count=$((installed_count + 1))
  done

  if [[ "$found_count" -eq 0 ]]; then
    rm -rf "$state_dir"
    fail "no skill directories with SKILL.md found in ${source_dir}"
  fi

  log "Activated repo-local Codex skills."
  log "  Source: ${source_dir}"
  log "  Destination: ${dest_dir}"
  log "  Linked: ${installed_count}"
  log "  Replaced conflicts: ${replaced_count}"
  log "  Already linked: ${skipped_count}"

  cat <<EOF
export CODEX_SKILLS_ACTIVE=1
export CODEX_SKILLS_STATE_DIR=$(shell_quote "$state_dir")
export CODEX_SKILLS_REPO_ROOT=$(shell_quote "$REPO_ROOT")
export CODEX_SKILLS_SOURCE=$(shell_quote "$source_dir")
export CODEX_SKILLS_DEST=$(shell_quote "$dest_dir")
export _CODEX_SKILLS_ENV_SCRIPT=$(shell_quote "$SCRIPT_PATH")
export _CODEX_SKILLS_OLD_PS1="\${PS1-}"
export PS1="(${prompt_label}) \${PS1-}"
deactivate_codex_skills() {
  eval "\$("\$_CODEX_SKILLS_ENV_SCRIPT" deactivate)"
}
EOF
}

deactivate() {
  local state_dir="${CODEX_SKILLS_STATE_DIR:-}"
  [[ -n "$state_dir" ]] || fail "CODEX_SKILLS_STATE_DIR is not set. Is the overlay active?"

  local manifest_path="${state_dir}/manifest.tsv"
  [[ -f "$manifest_path" ]] || fail "activation manifest not found: $manifest_path"

  local restored_count=0
  local removed_count=0

  local action skill_name target_path backup_path
  while IFS=$'\t' read -r action skill_name target_path backup_path; do
    case "$action" in
      same)
        ;;
      remove)
        if [[ -e "$target_path" || -L "$target_path" ]]; then
          rm -rf "$target_path"
        fi
        removed_count=$((removed_count + 1))
        ;;
      restore)
        if [[ -e "$target_path" || -L "$target_path" ]]; then
          rm -rf "$target_path"
        fi
        if [[ -e "$backup_path" || -L "$backup_path" ]]; then
          mv "$backup_path" "$target_path"
        else
          log "Warning: missing backup for ${skill_name} at ${backup_path}"
        fi
        restored_count=$((restored_count + 1))
        ;;
      *)
        fail "unknown manifest action: $action"
        ;;
    esac
  done < "$manifest_path"

  rm -rf "$state_dir"

  log "Deactivated repo-local Codex skills."
  log "  Restored conflicts: ${restored_count}"
  log "  Removed overlay-only links: ${removed_count}"

  cat <<'EOF'
if [ "${_CODEX_SKILLS_OLD_PS1+x}" = "x" ]; then
  export PS1="${_CODEX_SKILLS_OLD_PS1}"
  unset _CODEX_SKILLS_OLD_PS1
fi
unset CODEX_SKILLS_ACTIVE
unset CODEX_SKILLS_STATE_DIR
unset CODEX_SKILLS_REPO_ROOT
unset CODEX_SKILLS_SOURCE
unset CODEX_SKILLS_DEST
unset _CODEX_SKILLS_ENV_SCRIPT
unset -f deactivate_codex_skills 2>/dev/null || unfunction deactivate_codex_skills 2>/dev/null || true
EOF
}

main() {
  [[ $# -ge 1 ]] || {
    usage
    exit 1
  }

  case "$1" in
    activate)
      shift
      activate "$@"
      ;;
    deactivate)
      shift
      deactivate "$@"
      ;;
    --help|-h|help)
      usage
      ;;
    *)
      fail "unknown command: $1"
      ;;
  esac
}

main "$@"
