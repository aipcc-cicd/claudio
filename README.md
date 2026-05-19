# claudio

OCI image to make claude code portable; the model is being setup to use through Google Vertex AI API.

Additional functionality is provided through the [claudio-skills marketplace](https://github.com/aipcc-cicd/claudio-skills).

# Build

To build the container run the command:

```bash
make oci-build
```

This builds for the native architecture of the current platform.

You can customize the image name and tag:

```bash
IMAGE_REPO=ghcr.io/myorg/claudio IMAGE_TAG=latest make oci-build
```

By default, the Makefile uses Podman. To use Docker instead:

```bash
CONTAINER_MANAGER=docker make oci-build
```

Available targets:
- `oci-build` - Build container image for native architecture
- `oci-rebuild` - Remove existing image and rebuild from scratch (no cache)
- `oci-push` - Push container image
- `oci-tag` - Tag existing image with new tag
- `oci-manifest-build` - Create multi-arch manifest from arch-tagged images
- `oci-manifest-push` - Push manifest to registry
- `integrations-update` - Regenerate CI templates with current image version

## Claudio Skills Reference

During the image build, claudio clones [claudio-skills](https://github.com/aipcc-cicd/claudio-skills) into `/home/claudio/claudio-skills/` and:

1. **Fetches the specified git ref** — a branch, tag, or pull request head
2. **Runs tool installers** — iterates over `claudio-plugin/tools/*/install.sh` and executes each one (e.g. jq, kubectl)
3. **Installs Python dependencies** — installs packages from `claudio-plugin/tools/python/*-requirements.txt`
4. **Generates plugin configs** — registers skills and tools so Claude can discover them at runtime

The git ref is controlled by two build args:
- `CS_REF_TYPE` — one of `branch`, `tag`, or `pr` (default: `branch`)
- `CS_REF` — the branch name, tag name, or PR number (default: `main`)

```bash
# From a branch (default)
CS_REF_TYPE=branch CS_REF=main make oci-build

# From a tag
CS_REF_TYPE=tag CS_REF=v0.1.0 make oci-build

# From a pull request
CS_REF_TYPE=pr CS_REF=9 make oci-build
```

### Testing claudio-skills changes in downstream images

When developing changes to claudio-skills that affect a downstream image (e.g. aipcc-claudio), you can test end-to-end before merging:

1. Open a PR in claudio-skills (e.g. PR #9)
2. Build the claudio base image referencing that PR:
   ```bash
   CS_REF_TYPE=pr CS_REF=9 make oci-build
   ```
   This produces a local image tagged `quay.io/aipcc-cicd/claudio:v1.0.0-dev`.
3. In the downstream repo, point the `FROM` line at that local image (or tag it to match the expected base tag) and build:
   ```bash
   # In aipcc-claudio
   make oci-build
   ```
4. Run the resulting container and verify the changes work as expected.

# Usage

The recommended way to run claudio locally is through a wrapper script. It handles volume mounts, user namespace mapping, and environment loading automatically.

## Wrapper Script Setup

Copy or symlink [`cli/claudio`](cli/claudio) to `~/.local/bin/claudio`:

```bash
cp cli/claudio ~/.local/bin/claudio
chmod +x ~/.local/bin/claudio
```

The gcloud mount shares your host's Google Cloud credentials with the container. This is required because claudio uses Google Vertex AI as its default Claude API provider — `ANTHROPIC_VERTEX_PROJECT_ID` and `ANTHROPIC_VERTEX_PROJECT_QUOTA` identify the GCP project, while the gcloud credentials handle authentication. Make sure you're logged in on the host first (`gcloud auth application-default login`).

The kubeconfig mount expects a dedicated read-only kubeconfig at `~/.kube/claudio-reader.kubeconfig`. This keeps claudio's cluster access separate from your default kubeconfig.

The `.gitconfig`, `.ssh`, and SSH agent socket mounts are only needed if you want claudio to interact with git repositories over SSH or create SSH-signed commits. If you only work with HTTPS remotes and unsigned commits, these can be omitted.

Store your secrets in `~/.config/claudio/.env`:

```bash
GITLAB_TOKEN=...
ANTHROPIC_VERTEX_PROJECT_ID=...
ANTHROPIC_VERTEX_PROJECT_QUOTA=...
SLACK_XOXC_TOKEN=xoxc-...
SLACK_XOXD_TOKEN=xoxd-...
```

## Working with Local Projects

The wrapper script mounts `${PWD}` to `/home/claudio/workdir` automatically. Run `claudio` from the root of your project to work with local files:

```bash
cd ~/my-project
claudio
```

## Memory

Claudio bundles [MemPalace](https://github.com/MemPalace/mempalace) for persistent memory across sessions. Memory is **opt-in** — it is disabled by default and only activates when `MEMPAL_ENABLED` is set.

The palace is stored at a **fixed path inside the container**: `/home/claudio/.mempalace/palace`. Mount a persistent volume there to retain memory across runs.

Two Claude Code hooks activate automatically:

| Hook | Event | Purpose |
|---|---|---|
| `mempal_precompact_hook.sh` | `PreCompact` | Saves context before conversation compaction |
| `mempal_save_hook.sh` | `Stop` | Auto-saves memory every N exchanges on shutdown |

| Variable | Default | Purpose |
|---|---|---|
| `MEMPAL_SAVE_INTERVAL` | `5` | Number of conversation exchanges between automatic memory saves. Lower values save more frequently; higher values reduce overhead. |

### Enabling memory locally

Mount a host directory at the palace path and set `MEMPAL_ENABLED`:

```bash
podman run -it --rm --userns=keep-id \
  -v ${HOME}/.config/gcloud:/home/claudio/.config/gcloud \
  -v ${PWD}:/home/claudio/workdir \
  -v ${HOME}/.local/share/claudio-memory:/home/claudio/.mempalace/palace \
  -e ANTHROPIC_VERTEX_PROJECT_ID="${ANTHROPIC_VERTEX_PROJECT_ID}" \
  -e ANTHROPIC_VERTEX_PROJECT_QUOTA="${ANTHROPIC_VERTEX_PROJECT_QUOTA}" \
  -e MEMPAL_ENABLED=true \
  -e MEMPAL_SAVE_INTERVAL=5 \
  quay.io/aipcc-cicd/claudio:v0.6.0
```

Add it to your wrapper script and `.env` file to make it permanent:

```bash
# in ~/.config/claudio/.env
MEMPAL_SAVE_INTERVAL=5
```

```bash
# in the wrapper script, add the volume mount and env vars
  -v ${HOME}/.local/share/claudio-memory:/home/claudio/.mempalace/palace \
  -e MEMPAL_ENABLED="${MEMPAL_ENABLED:-false}" \
  -e MEMPAL_SAVE_INTERVAL="${MEMPAL_SAVE_INTERVAL:-5}" \
```

### Enabling memory in GitLab CI

Mount a persistent volume at the palace path and pass `MEMPAL_ENABLED`:

```yaml
my-claudio-job:
  extends: .claudio
  variables:
    CLAUDIO_PROMPT: "Analyze the latest MRs and report to Slack"
    MEMPAL_ENABLED: "true"
  volumes:
    - claudio-memory:/home/claudio/.mempalace/palace
```

## One-time Prompt

```bash
claudio -p "do something for me Claudio"
```

## Git Integration

Git identity, commit signing, and remote authentication can be configured via environment variables. This is useful in CI pipelines and containerized environments where mounting `.gitconfig` is not practical.

| Variable | Description |
|---|---|
| `GIT_USER_NAME` | Sets `git config --global user.name` |
| `GIT_USER_EMAIL` | Sets `git config --global user.email` |
| `GIT_SSH_SIGNING_KEY` | Path to an SSH key for commit signing. Enables `gpg.format ssh` and `commit.gpgsign true` |
| `GITLAB_TOKEN` | GitLab personal access token, used by `glab` for API operations |
| `GITLAB_HOST` | GitLab instance URL, used by `glab` (defaults to `gitlab.com`) |

These are optional — if unset, git uses whatever config is already present (e.g. a mounted `.gitconfig`). This handles a single git identity. For multi-instance setups, configure per-host credentials in the configuration file (`~/.config/glab-cli/config.yml`).

## GitLab CI Integration

Claudio provides a reusable GitLab CI template for running claudio jobs in your pipelines. Include it in your project's `.gitlab-ci.yml`:

```yaml
include:
  - project: 'aipcc-cicd/claudio'
    file: 'integrations/gitlab-ci/claudio.yml'

my-claudio-job:
  extends: .claudio
  variables:
    CLAUDIO_PROMPT: "Analyze the latest MRs and report to Slack"
```

The `.claudio` template uses the claudio image directly as the job container. You just set `CLAUDIO_PROMPT` and claudio runs with the entrypoint handling gcloud auth and setup.

Available variables:
- `CLAUDIO_PROMPT` (required) — the prompt to run
- `CLAUDIO_IMAGE` — override the claudio image (default: current release version)
- `CLAUDIO_EXTRA_ARGS` — extra arguments passed to claudio
- `CLAUDIO_STREAM` — set to `1` to enable human-readable streaming output in the job log
- `CLAUDIO_LOG_FILE` — write a plain-text log (no ANSI codes) to this path (streaming mode only)
- `CLAUDIO_WRAP` — word-wrap output at N columns, `0` to disable (streaming mode only)
- `NO_COLOR` — set to `1` to disable ANSI color codes in streaming output

### Streaming mode

When `CLAUDIO_STREAM=1`, the entrypoint automatically pipes Claude's output through a stream parser that renders tool calls, thinking, token stats, and errors as readable log lines. The raw `--output-format stream-json` flags are added automatically — you don't need to include them in `CLAUDIO_EXTRA_ARGS`.

```yaml
my-claudio-job:
  extends: .claudio
  variables:
    CLAUDIO_STREAM: "1"
    CLAUDIO_LOG_FILE: "claudio-stream.log"
    CLAUDIO_PROMPT: "Do something useful"
```

The template is generated from `integrations/gitlab-ci/template/claudio.yml`. When preparing a release, run `make integrations-update` to regenerate the template with the current version, then commit the result.

Downstream projects can extend this template to add their own secret management.
