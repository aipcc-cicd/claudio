# Claudio — CLAUDE.md

## Project Overview

**Claudio** is an OCI container image that packages Claude Code CLI into a portable, CI/CD-friendly container. It uses Google Vertex AI as the Claude API backend by default and bundles skills/plugins from the [claudio-skills](https://github.com/aipcc-cicd/claudio-skills) marketplace.

Primary use cases:
- Running Claude Code in GitLab CI pipelines via a reusable `.claudio` job template
- Providing a portable AI development assistant that can be mounted into any working directory

## Key Files

| File | Purpose |
|---|---|
| `Containerfile` | Multi-stage OCI image build (preparer → final) |
| `entrypoint.sh` | Container startup: configures git identity, SSH signing key, gcloud auth, starts MemPalace if `MEMPAL_DIR` is set |
| `Makefile` | Build, tag, push, and release automation |
| `conf/.claude.json` | Claude client config template baked into the image |
| `scripts/generate-plugin-configs.sh` | Registers claudio-skills as Claude plugins at build time |
| `integrations/gitlab-ci/claudio.yml` | Generated GitLab CI reusable job template |
| `.github/workflows/build.yml` | Multi-arch (amd64 + arm64) CI build pipeline |
| `.github/workflows/push-pr-images.yml` | Publishes PR images to GHCR |
| `renovate.json` | Automated dependency updates (Claude Code, gcloud SDK versions) |

## Build & Run

### Build the image

```bash
make oci-build                          # native arch, defaults
CONTAINER_MANAGER=docker make oci-build # use Docker instead of Podman

# Pin to a specific claudio-skills ref
CS_REF_TYPE=tag   CS_REF=v0.1.0 make oci-build
CS_REF_TYPE=branch CS_REF=main  make oci-build
CS_REF_TYPE=pr    CS_REF=9      make oci-build

# Custom image repo/tag
IMAGE_REPO=ghcr.io/myorg/claudio IMAGE_TAG=latest make oci-build
```

### Run locally

```bash
podman run -it --rm --userns=keep-id \
  -v ${HOME}/.config/gcloud:/home/claudio/.config/gcloud \
  -v ${PWD}:/home/claudio/workdir \
  -e ANTHROPIC_VERTEX_PROJECT_ID="my-gcp-project" \
  quay.io/aipcc-cicd/claudio:latest
```

## Architecture

- **Base images**: `ubi10` (preparer) → `ubi10/python-312-minimal` (final)
- **Key installed tools**: Claude Code CLI, Google Cloud SDK, Podman, Skopeo, git, jq
- **Runs as**: non-root user `claudio` (uid 1000)
- **Multi-arch**: amd64 and arm64 manifests published to GHCR (dev/PRs) and Quay (releases)

## Dependencies & Versions (managed by Renovate)

- Claude Code CLI: pinned in `Containerfile` (`ARG CLAUDE_CODE_VERSION`)
- Google Cloud SDK: pinned in `Containerfile` (`ARG GCLOUD_SDK_VERSION`)
- claudio-skills: resolved at build time via `CS_REF`/`CS_REF_TYPE`; cache invalidated automatically via `CS_CACHE_KEY` (resolved commit SHA)

## Release Process

1. Bump `VERSION` in `Makefile`
2. Tag the commit: `make tag` (creates `v<VERSION>` git tag)
3. Push the tag — the `build.yml` workflow publishes to Quay and GHCR

Current version: `0.6.0-dev`

## CI/CD

- **PRs**: builds both arches, uploads tar artifacts, `push-pr-images.yml` loads and pushes to GHCR with PR tag
- **`main` push**: builds + pushes `latest` multi-arch manifest to GHCR
- **Version tags**: builds + pushes versioned multi-arch manifest to Quay (`quay.io/aipcc-cicd/claudio`)

## GitLab CI Integration

Users include the reusable template and extend `.claudio`:

```yaml
include:
  - project: 'aipcc-cicd/claudio'
    file: 'integrations/gitlab-ci/claudio.yml'

my-job:
  extends: .claudio
  variables:
    CLAUDIO_PROMPT: "Review this MR and suggest improvements"
```

## Memory (MemPalace)

Persistent memory is provided by [MemPalace](https://github.com/MemPalace/mempalace) and is **opt-in** via the `MEMPAL_ENABLED` env var.

The palace is stored at a **fixed path inside the container**: `/home/claudio/.mempalace/palace`. Mount a persistent volume there to retain memory across sessions.

| Variable | Default | Purpose |
|---|---|---|
| `MEMPAL_ENABLED` | `"false"` (disabled) | Enable flag for MemPalace hooks. Set to `true` to activate. The palace is always at `/home/claudio/.mempalace/palace` — mount a volume there to persist memory across runs. |
| `MEMPAL_SAVE_INTERVAL` | `5` | Number of conversation exchanges between automatic memory saves on shutdown (passed to `mempal_save_hook.sh`). Lower values save more frequently; higher values reduce overhead. |

Two hooks are always registered in `conf/.claude/settings.json` but short-circuit with `exit 0` when `MEMPAL_ENABLED` is unset:

- **PreCompact** → `mempal_precompact_hook.sh` — saves context before compaction
- **Stop** → `mempal_save_hook.sh` — auto-saves every N exchanges on shutdown

Hook scripts are downloaded at build time from the `v${MEMPALACE_V}` tag of the upstream repo, keeping them in sync with the installed pip package version. Renovate bumps `MEMPALACE_V` in the Containerfile and the hook URLs update automatically.

### Local usage with memory

```bash
podman run -it --rm --userns=keep-id \
  -v ${HOME}/.config/gcloud:/home/claudio/.config/gcloud \
  -v ${PWD}:/home/claudio/workdir \
  -v ${HOME}/.local/share/claudio-memory:/home/claudio/.mempalace/palace \
  -e ANTHROPIC_VERTEX_PROJECT_ID="..." \
  -e MEMPAL_ENABLED=true \
  -e MEMPAL_SAVE_INTERVAL=5 \
  quay.io/aipcc-cicd/claudio:v0.6.0
```

## License

Apache 2.0
