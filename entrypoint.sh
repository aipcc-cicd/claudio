#!/bin/bash

# Default DEBUG to false if not set
DEBUG="${DEBUG:-false}"

# Enable debug if DEBUG is true
if [ "$DEBUG" = "true" ]; then
  set -x
fi

ADC_PATH="${HOME}/.config/gcloud/application_default_credentials.json"

###################
#### Functions ####
###################

# Function to check token validity
check_adc() {
  if [ ! -f "$ADC_PATH" ]; then
    return 1
  fi
  if gcloud auth application-default print-access-token --quiet >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

##############
#### Main ####
##############

# Auth
if ! check_adc; then
  echo "Running gcloud auth application-default login..."
  gcloud auth application-default login --quiet
  # Setup project and quota
  gcloud config set project ${ANTHROPIC_VERTEX_PROJECT_ID}
  gcloud auth application-default set-quota-project ${ANTHROPIC_VERTEX_PROJECT_QUOTA}
fi

# Load custom commands from /workspace/.claude/commands if present
WORKSPACE_COMMANDS_DIR="/workspace/.claude/commands"
CLAUDE_COMMANDS_DIR="${HOME}/.claude/commands"

if [ -d "$WORKSPACE_COMMANDS_DIR" ]; then
  echo "Loading custom commands from ${WORKSPACE_COMMANDS_DIR}..."

  # Create commands directory if it doesn't exist
  mkdir -p "$CLAUDE_COMMANDS_DIR"

  # Copy all command files from workspace to Claude's commands directory
  for cmd_file in "$WORKSPACE_COMMANDS_DIR"/*.md; do
    # Check if any .md files exist
    if [ -e "$cmd_file" ]; then
      cmd_name=$(basename "$cmd_file")
      echo "  - Loading command: ${cmd_name%.md}"
      cp "$cmd_file" "$CLAUDE_COMMANDS_DIR/$cmd_name"
    fi
  done

  echo "Custom commands loaded successfully."
fi

# Run claude
# https://github.com/anthropics/claude-code/issues/2425
# When this is fixed just use
# exec claude "$@"
SESSIONID=$(uuidgen)
CONTEXT_FILE=~/context.md
: > "$CONTEXT_FILE" 
for c in ~/.claude/context.d/*.md; do
  tee -a "$CONTEXT_FILE" < "$c"
done
claude -p "$(cat "$CONTEXT_FILE")" --session-id "$SESSIONID" > /dev/null
exec claude -r ${SESSIONID} --mcp-config ~/.claude/mcp.d/*.json "$@"
