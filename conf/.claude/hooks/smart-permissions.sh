#!/usr/bin/env bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

INSTALLED="${HOME}/.claude/plugins/installed_plugins.json"
[ -f "$INSTALLED" ] || exit 0

mapfile -t PLUGIN_PATHS < <(jq -r '.plugins[] | .[].installPath' "$INSTALLED" 2>/dev/null)
[ ${#PLUGIN_PATHS[@]} -eq 0 ] && exit 0

# Extract the executable: strip leading bash/sh/python wrapper if present
EXECUTABLE=$(echo "$COMMAND" | awk '{
    if ($1 ~ /^(bash|sh|python[0-9.]*)$/) print $2; else print $1
}')

# Resolve to absolute path
EXECUTABLE=$(realpath -q "$EXECUTABLE" 2>/dev/null || echo "$EXECUTABLE")

for plugin_path in "${PLUGIN_PATHS[@]}"; do
    case "$EXECUTABLE" in
        "${plugin_path}"/*)
            jq -n '{
                hookSpecificOutput: {
                    hookEventName: "PreToolUse",
                    permissionDecision: "allow",
                    permissionDecisionReason: "Command executes a plugin script"
                }
            }'
            exit 0
            ;;
    esac
done

exit 0
