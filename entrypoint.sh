#!/bin/bash

# Default DEBUG to false if not set
DEBUG="${DEBUG:-false}"

# Enable debug if DEBUG is true
if [ "$DEBUG" = "true" ]; then
  set -x
fi

ADC_PATH="${GOOGLE_APPLICATION_CREDENTIALS:-${HOME}/.config/gcloud/application_default_credentials.json}"

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

# Configure git identity (defaults can be overridden via env vars)
if [ -n "${GIT_USER_NAME:-}" ]; then
  git config --global user.name "$GIT_USER_NAME"
fi
if [ -n "${GIT_USER_EMAIL:-}" ]; then
  git config --global user.email "$GIT_USER_EMAIL"
fi

# Configure git commit signing
if [ -n "${GIT_SSH_SIGNING_KEY:-}" ]; then
  chmod 600 "$GIT_SSH_SIGNING_KEY"
  git config --global gpg.format ssh
  git config --global user.signingkey "$GIT_SSH_SIGNING_KEY"
  git config --global commit.gpgsign true
fi

# Change to workdir if it exists (for mounted volumes)
if [ -d "$HOME/workdir" ]; then
  cd "$HOME/workdir"
fi

# Generate CLAUDE.md with imports from context.d
CLAUDE_MD="${HOME}/.claude/CLAUDE.md"
: >"$CLAUDE_MD"
for c in ~/.claude/context.d/*.md; do
  [ -f "$c" ] && echo "@$c" >>"$CLAUDE_MD"
done

# Run claude
exec claude "$@"
