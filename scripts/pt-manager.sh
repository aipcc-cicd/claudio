#!/usr/bin/env bash
set -euo pipefail

settings="${HOME}/.claude/settings.json"
[ -f "$settings"  ] || exit 0

installed="${HOME}/.claude/plugins/installed_plugins.json"
[ -f "$installed" ] || exit 0

echo "Updating permissions for installed plugins..." >&2
new_perms=()
while IFS=$'\t' read -r key path; do
    plugin_name="${key%@*}"
    [ -d "${path}/skills" ] || continue
    while IFS= read -r skill_dir; do
        new_perms+=("Skill(${plugin_name}:$(basename "$skill_dir"))")
    done < <(find "${path}/skills" -maxdepth 1 -mindepth 1 -type d)
done < <(jq -r '.plugins | to_entries[] | .key as $k | .value[] | [$k, .installPath] | @tsv' "$installed")

if [ ${#new_perms[@]} -gt 0 ]; then
    tmp=$(mktemp)
    perms_json=$(jq -cn '$ARGS.positional' --args "${new_perms[@]}")
    jq --argjson p "$perms_json" \
        '.permissions.allow = (((.permissions.allow // []) + $p) | unique)' \
        "$settings" > "$tmp"
    mv "$tmp" "$settings"
fi

# Register PreToolUse hook to auto-allow commands that invoke plugin scripts.
# Workaround for broken permission matching in Claude Code:
# https://github.com/anthropics/claude-code/issues/14956
# https://github.com/anthropics/claude-code/issues/30519
echo "Registering PreToolUse hook for plugin script permissions..." >&2
hook_script="${HOME}/.claude/hooks/smart-permissions.sh"
if [ -f "$hook_script" ]; then
    tmp=$(mktemp)
    jq --arg cmd "bash ${hook_script}" '.hooks.PreToolUse = ((.hooks.PreToolUse // []) + [{"matcher": "Bash", "hooks": [{"type": "command", "command": $cmd}]}])' \
        "$settings" > "$tmp"
    mv "$tmp" "$settings"
fi

echo "Running installation scripts for installed plugins..." >&2
while IFS= read -r location; do
    while IFS= read -r script; do
        bash "$script"
    done < <(find "$location" -path "*/tools/*/install.sh" -type f 2>/dev/null)
    while IFS= read -r req; do
        pip install --no-cache-dir -r "$req"
    done < <(find "$location" -path "*/tools/python/*-requirements.txt" -type f 2>/dev/null)
done < <(jq -r '.plugins[] | .[].installPath' "$installed")

echo "Running pt-manager to install Python dependencies for installed plugins..." >&2
deps=()
while IFS= read -r path; do
    while IFS= read -r script; do
        grep -q "uv run --script" "$script" 2>/dev/null || continue
        while IFS= read -r dep; do
            [ -n "$dep" ] && deps+=("$dep")
        done < <(
            sed -n '/^# \/\/\/ script/,/^# \/\/\/$/p' "$script" |
            sed -n '/dependencies = \[/,/\]/p'          |
            grep -oE '"[^"]+"'                           |
            tr -d '"'
        )
    done < <(find "$path" -name "*.py" -type f 2>/dev/null)
done < <(jq -r '.plugins[] | .[].installPath' "$installed")

if [ ${#deps[@]} -eq 0 ]; then exit 0; fi

printf '%s\n' "${deps[@]}" | sort -u | xargs pip install --no-cache-dir
