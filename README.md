# claudio

OCI image to make claude code portable; the model is being setup to use through Google Vertex AI API. 

The image also contains a list of curated mcp servers setup and a base memory for claude ensuring it uses them as expected. 

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

## Gitlab CICD

To manage gitlab CICD integration claudio will use https://gitlab.com/fforster/gitlab-mcp 

For Auth check https://gitlab.com/fforster/gitlab-mcp#authentication

## Openshift / K8s 

To manage Openshift / K8s integration claudio will use https://github.com/containers/kubernetes-mcp-server

We will need to add the kubeconfig as part of the execution and set its path with `K8S_MCP_KUBECONFIG_PATH`

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

# Usage

In order to make claudio OpenShift compliant the default user for the container is default, it is also part of the root group, under some circumstances when mapping host volumes podman is not able to access the volume (even with the right permissions), to avoid that siatuion we suggest when running locally to use `--user 0` to enforce default behavior by podman.

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
        -e GITLAB_URL='https://gitlab.com' \
        -e GITLAB_TOKEN='...' \
        -e ANTHROPIC_VERTEX_PROJECT_ID=... \
        -e ANTHROPIC_VERTEX_PROJECT_QUOTA=... \
        -e SLACK_MCP_XOXC_TOKEN='xoxc-...' \
        -e SLACK_MCP_XOXD_TOKEN='xoxd-...' \
        -e K8S_MCP_KUBECONFIG_PATH=/opt/k8s/kubeconfig \
        quay.io/redhat-aipcc/claudio:v1.0.0-dev
```

Claudio on a host where user is already logged in on gcloud:

```bash
# Run claudio
podman run -it --rm -user 0 \
        -v ${PWD}/kubecofing:/opt/k8s/kubeconfig:z \
        -v /home/$USER/.conf/gcloud:/root/.config/gcloud:z \
        -e GITLAB_URL='https://gitlab.com' \
        -e GITLAB_TOKEN='...' \
        -e ANTHROPIC_VERTEX_PROJECT_ID=... \
        -e ANTHROPIC_VERTEX_PROJECT_QUOTA=... \
        -e SLACK_MCP_XOXC_TOKEN='xoxc-...' \
        -e SLACK_MCP_XOXD_TOKEN='xoxd-...' \
        -e K8S_MCP_KUBECONFIG_PATH=/opt/k8s/kubeconfig \
        quay.io/redhat-aipcc/claudio:v1.0.0-dev
```

Claudio one-time prompt

```bash
# Run claudio with a prompt
podman run -it --rm --user 0 \
        -v ${PWD}/kubecofing:/opt/k8s/kubeconfig:z \
        -v /home/$USER/.conf/gcloud:/root/.config/gcloud:z \
        -e GITLAB_URL='https://gitlab.com' \
        -e GITLAB_TOKEN='...' \
        -e ANTHROPIC_VERTEX_PROJECT_ID=... \
        -e ANTHROPIC_VERTEX_PROJECT_QUOTA=... \
        -e SLACK_MCP_XOXC_TOKEN='xoxc-...' \
        -e SLACK_MCP_XOXD_TOKEN='xoxd-...' \
        -e K8S_MCP_KUBECONFIG_PATH=/opt/k8s/kubeconfig \
        quay.io/redhat-aipcc/claudio:v1.0.0-dev \
                -p "do something for me Claudio"
```

# Custom Commands

Claudio supports loading project-specific slash commands from your workspace. This enables reusable command templates for common workflows.

## Creating Custom Commands

1. Create a `.claude/commands` directory in your workspace:
```bash
mkdir -p .claude/commands
```

2. Add command files in Markdown format (`.md` extension):
```bash
cat > .claude/commands/create-release.md << 'EOF'
# Create RHAIIS Release

Create production Release YAMLs for RHAIIS version $1.

Steps:
1. Find Git SHA for tag v$1
2. List all stage releases for that SHA
3. Extract snapshot IDs from each component
4. Generate 5 production Release YAML files
EOF
```

3. Mount your workspace when running Claudio:
```bash
podman run -it --rm --user 0 \
        -v ${PWD}:/workspace:z \
        -v ${PWD}/kubeconfig:/opt/k8s/kubeconfig:z \
        -e ANTHROPIC_VERTEX_PROJECT_ID=... \
        -e ANTHROPIC_VERTEX_PROJECT_QUOTA=... \
        -e K8S_MCP_KUBECONFIG_PATH=/opt/k8s/kubeconfig \
        quay.io/redhat-aipcc/claudio:v1.0.0-dev
```

## Using Custom Commands

### Interactive Mode
In the Claude Code session, use your slash command:
```
/create-release 3.2.3
```

### Non-Interactive Mode
Execute slash commands directly when starting the container:
```bash
# Run a custom command with arguments
podman run -it --rm --user 0 \
        -v ${PWD}:/workspace:z \
        -v ${PWD}/kubeconfig:/opt/k8s/kubeconfig:z \
        -e ANTHROPIC_VERTEX_PROJECT_ID=... \
        -e ANTHROPIC_VERTEX_PROJECT_QUOTA=... \
        -e K8S_MCP_KUBECONFIG_PATH=/opt/k8s/kubeconfig \
        quay.io/redhat-aipcc/claudio:v1.0.0-dev \
        /create-release 3.2.3
```

## Command Arguments

Commands support argument substitution:
- `$ARGUMENTS` - All arguments as a single string
- `$1`, `$2`, `$3`, etc. - Individual positional arguments

Example command with multiple arguments:
```markdown
# Deploy to Environment

Deploy RHAIIS version $1 to environment $2.

Steps:
1. Verify version $1 exists in registry
2. Update deployment manifests for $2 environment
3. Apply changes to cluster
4. Monitor rollout status
```

Usage: `/deploy-to-env 3.2.3 staging`
