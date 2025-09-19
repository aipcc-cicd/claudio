#!/bin/bash

set -ex

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

# Run claude
# https://github.com/anthropics/claude-code/issues/2425
# When this is fixed just use
# exec claude "$@"
SESSIONID=$(uuidgen)
claude -p "$(cat ~/CLAUDE.md)" --session-id ${SESSIONID} > /dev/null
exec claude -r ${SESSIONID} --mcp-config ~/.claude/.mcp.json "$@"


