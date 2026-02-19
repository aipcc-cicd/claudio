# claudio

OCI image to make claude code portable; the model is being setup to use through Google Vertex AI API.

The image includes the Slack MCP server for communication, along with `glab` and `kubectl` CLIs. Additional functionality is provided through the [claudio-skills marketplace](https://github.com/aipcc-cicd/claudio-skills).

# Integrations

## Slack

To manage slack integration claudio will use https://github.com/korotovsky/slack-mcp-server, 

To get values for them the easiest way is to authenticate to your slack workspace in chrome/chromium browser

On same page go to More Tools -> Developer Tools

On Developer Tools go to:

* XOXC: Application -> Storage -> Local Storage -> https>//app.slack.com -> localConfig_v2 (key) -> 'token' key inside the json value 
* XOXD: Application -> Storage -> Cookies -> https>//app.slack.com -> d (key)

Since it is slack enterpise we need to get value for User-Agent. To get it from same place we check Networking and check request headers to get the value,
it should be something similar to `Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36`

Disclaimer, the first time you reuse those Tokens you will probably be signed off as precaution, the second time you sign in the tokens should last.

## GitLab

GitLab integration is provided through the `glab` CLI tool and the claudio-skills marketplace. The `glab` CLI is pre-installed in the container.

## Kubernetes / OpenShift

Kubernetes and OpenShift management is handled through `kubectl` (pre-installed) and skills from the claudio-skills marketplace.

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
- `oci-push` - Push container image
- `oci-tag` - Tag existing image with new tag
- `oci-manifest-build` - Create multi-arch manifest from arch-tagged images
- `oci-manifest-push` - Push manifest to registry

## Claudio Skills Reference

During the image build, claudio clones [claudio-skills](https://github.com/aipcc-cicd/claudio-skills) into `/home/default/claudio-skills/` and:

1. **Fetches the specified git ref** — a branch, tag, or pull request head
2. **Runs tool installers** — iterates over `claudio-plugin/tools/*/install.sh` and executes each one (e.g. jq, python dependencies)
3. **Generates plugin configs** — registers skills and tools so Claude can discover them at runtime

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

In order to make claudio OpenShift compliant the default user for the container is default, it is also part of the root group, under some circumstances when mapping host volumes podman is not able to access the volume (even with the right permissions), to avoid that siatuion we suggest when running locally to use `--user 0` to enforce default behavior by podman.

## Working with Local Projects

Claudio supports mounting your local project directory for interactive development. When you mount a directory to `/home/default/workdir`, claudio will automatically change to that directory before starting the Claude session, allowing you to work with your local files.

Example mounting your current directory:

```bash
podman run -it --rm --user 0 \
        -v ${PWD}:/home/default/workdir:z \
        -v claudio-gcp:/root/.config/gcloud:Z \
        -v claudio-mcp-slack:/root/claude/mcp/slack:Z \
        -e GITLAB_TOKEN='...' \
        -e ANTHROPIC_VERTEX_PROJECT_ID=... \
        -e ANTHROPIC_VERTEX_PROJECT_QUOTA=... \
        -e SLACK_MCP_XOXC_TOKEN='xoxc-...' \
        -e SLACK_MCP_XOXD_TOKEN='xoxd-...' \
        -e K8S_MCP_KUBECONFIG_PATH=/opt/k8s/kubeconfig \
        quay.io/redhat-aipcc/claudio:v1.0.0-dev
```

This allows you to use claudio with your local codebase, making file edits, running commands, and interacting with your project files directly.

## Basic Setup

```bash
# Create a volume to hold the auth for gcloud
podman volume create claudio-gcp

# Create a volume to hold cache for mcp slack
podman volume create claudio-mcp-slack

# Run claudio
podman run -it --rm --user 0 \
        -v ${PWD}/kubecofing:/opt/k8s/kubeconfig:z \
        # Optional
        -v claudio-gcp:/root/.config/gcloud:Z \
        # Optional
        -v claudio-mcp-slack:/root/claude/mcp/slack:Z \
        -e GITLAB_TOKEN='...' \
        -e ANTHROPIC_VERTEX_PROJECT_ID=... \
        -e ANTHROPIC_VERTEX_PROJECT_QUOTA=... \
        -e SLACK_MCP_XOXC_TOKEN='xoxc-...' \
        -e SLACK_MCP_XOXD_TOKEN='xoxd-...' \
        -e K8S_MCP_KUBECONFIG_PATH=/opt/k8s/kubeconfig \
        quay.io/aipcc-cicd/claudio:v1.0.0-dev
```

Claudio on a host where user is already logged in on gcloud:

```bash
# Run claudio
podman run -it --rm -user 0 \
        -v ${PWD}/kubecofing:/opt/k8s/kubeconfig:z \
        -v /home/$USER/.conf/gcloud:/root/.config/gcloud:z \
        -e GITLAB_TOKEN='...' \
        -e ANTHROPIC_VERTEX_PROJECT_ID=... \
        -e ANTHROPIC_VERTEX_PROJECT_QUOTA=... \
        -e SLACK_MCP_XOXC_TOKEN='xoxc-...' \
        -e SLACK_MCP_XOXD_TOKEN='xoxd-...' \
        -e K8S_MCP_KUBECONFIG_PATH=/opt/k8s/kubeconfig \
        quay.io/aipcc-cicd/claudio:v1.0.0-dev
```

Claudio one-time prompt

```bash
# Run claudio
podman run -it --rm -user 0 \
        -v ${PWD}/kubecofing:/opt/k8s/kubeconfig:z \
        -v /home/$USER/.conf/gcloud:/root/.config/gcloud:z \
        -e GITLAB_TOKEN='...' \
        -e ANTHROPIC_VERTEX_PROJECT_ID=... \
        -e ANTHROPIC_VERTEX_PROJECT_QUOTA=... \
        -e SLACK_MCP_XOXC_TOKEN='xoxc-...' \
        -e SLACK_MCP_XOXD_TOKEN='xoxd-...' \
        -e K8S_MCP_KUBECONFIG_PATH=/opt/k8s/kubeconfig \
        quay.io/aipcc-cicd/claudio:v1.0.0-dev \
                -p "do something for me Claudio"
```
