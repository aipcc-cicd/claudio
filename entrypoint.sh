#!/bin/bash

# Default DEBUG to false if not set
DEBUG="${DEBUG:-false}"

# Enable debug if DEBUG is true
if [ "$DEBUG" = "true" ]; then
  set -x
fi

ADC_PATH="${GOOGLE_APPLICATION_CREDENTIALS:-${HOME}/.config/gcloud/application_default_credentials.json}"
CLAUDIO_RESULT_FILE="${CLAUDIO_RESULT_FILE:-}"
CLAUDIO_VALIDATE_RESULT="${CLAUDIO_VALIDATE_RESULT:-true}"
CLAUDIO_EVALUATION_PROMPT="${CLAUDIO_EVALUATION_PROMPT:-$(cat <<'EOF'
Read this Claude Code session log and determine whether the task completed successfully.

Your entire response must be a single word or line — no preamble, no explanation:

SUCCESS
FAILURE: <short reason>

Rules for FAILURE:
- the agent abandoned the task
- commands or tool calls failed without recovery
- tests failed
- the requested work was only partially completed
- the final state is uncertain
- the task could not be verified as complete
EOF
)}"

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

# --- Non-streaming mode: transparent passthrough ---
if [ "${CLAUDIO_STREAM:-}" != "1" ]; then
  exec claude "$@"
fi

# --- CI streaming mode ---
stream_args=()
[ -n "${CLAUDIO_LOG_FILE:-}" ] && stream_args+=(--log-file "$CLAUDIO_LOG_FILE")
[ -n "${CLAUDIO_WRAP:-}" ]     && stream_args+=(--wrap "$CLAUDIO_WRAP")
[ "${NO_COLOR:-}" = "1" ]        && stream_args+=(--no-color)

FIFO_DIR=$(mktemp -d)
FIFO="$FIFO_DIR/stream.fifo"
mkfifo "$FIFO"

claude \
    --output-format stream-json \
    --include-partial-messages \
    --include-hook-events \
    --verbose \
    "$@" > "$FIFO" &
claude_pid=$!

python3 -u /usr/local/bin/stream-claude.py "${stream_args[@]}" < "$FIFO" &
stream_pid=$!

_on_signal() {
  kill "$claude_pid" "$stream_pid" 2>/dev/null || true
}

cleanup() {
  rm -rf "$FIFO_DIR"
}

trap '_on_signal; cleanup' TERM INT EXIT

wait "$stream_pid" 2>/dev/null && stream_rc=0 || stream_rc=$?

# If stream dies, stop claude to avoid blocking on FIFO
kill "$claude_pid" 2>/dev/null || true
wait "$claude_pid" 2>/dev/null && claude_rc=0 || claude_rc=$?

# 143 = SIGTERM (expected when we kill claude after stream ends)
if [ "$stream_rc" -ne 0 ]; then exit "$stream_rc"; fi
if [ "$claude_rc" -ne 0 ] && [ "$claude_rc" -ne 143 ]; then exit "$claude_rc"; fi

# Result check: use a second Claude call to evaluate whether the task
# actually completed successfully based on the session log.
if [ -n "${CLAUDIO_RESULT_FILE}" ] && [ -s "${CLAUDIO_LOG_FILE:-}" ]; then
  echo "=== Evaluating task result ==="

  eval_output=""
  if ! eval_output=$(tail -c "${CLAUDIO_RESULT_MAX_CHARS:-50000}" "${CLAUDIO_LOG_FILE}" | \
    claude -p "${CLAUDIO_EVALUATION_PROMPT}" \
      --model "${CLAUDIO_EVALUATION_MODEL:-claude-haiku-4-5-20251001}" \
      --no-session-persistence)
  then
    echo "ERROR: Failed to evaluate task result"
    exit 1
  fi

  if [[ "$CLAUDIO_VALIDATE_RESULT" == "true" ]]; then
    # Extract the verdict line — models sometimes wrap it in extra text
    verdict=$(echo "$eval_output" | grep -oE '^(SUCCESS|FAILURE: .+)' | head -n1)
    if [ -z "$verdict" ]; then
      verdict=$(echo "$eval_output" | grep -oE '(SUCCESS|FAILURE: .+)' | head -n1)
    fi
    echo "${verdict:-$eval_output}" > "${CLAUDIO_RESULT_FILE}"

    validate_result
    exit $?
  else
    echo "$eval_output" > "${CLAUDIO_RESULT_FILE}"
  fi
fi

exit 0
