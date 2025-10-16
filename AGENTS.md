# Claudio - Portable Claude Code Container

## Project Overview

**Claudio** is a containerized, production-ready deployment of Anthropic's Claude Code CLI, designed for enterprise environments. It packages Claude Code with pre-configured MCP (Model Context Protocol) servers and curated context to enable AI-assisted software engineering workflows in cloud-native, Kubernetes, and OpenShift environments.

**Key Value Proposition**: Claudio makes Claude Code portable and repeatable by bundling it with enterprise integrations (Slack, GitLab, Kubernetes), authentication mechanisms (Google Cloud Vertex AI), and operational best practices into a single OCI container image.

## Project Purpose

This project serves DevOps, SRE, and Platform Engineering teams who need:

1. **Consistent AI tooling** across development, CI/CD, and production environments
2. **Enterprise integrations** pre-configured for Slack communications, GitLab CI/CD, and Kubernetes operations
3. **OpenShift compliance** with proper user permissions and security constraints
4. **Automated dependency management** via Renovate for Claude Code and MCP servers
5. **Multi-architecture support** (amd64/arm64) for cloud and edge deployments

## Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────────┐
│                    Claudio Container                        │
├─────────────────────────────────────────────────────────────┤
│  Base: UBI 10 Node.js 22                                   │
│  ├─ Claude Code CLI (v2.0.14)                              │
│  ├─ Google Cloud SDK (v542.0.0) - Vertex AI Authentication │
│  ├─ Container Tools: skopeo, podman, jq                    │
│  └─ MCP Servers:                                           │
│     ├─ Slack MCP (v1.1.26) - Team communications          │
│     ├─ GitLab MCP (v1.31.1) - CI/CD integration           │
│     └─ Kubernetes MCP (v0.0.53) - Cluster operations      │
├─────────────────────────────────────────────────────────────┤
│  Configuration (/home/default/.claude/)                     │
│  ├─ context.d/CLAUDE-base.md - Base context/memory        │
│  ├─ mcp.d/mcp-base.json - MCP server configurations       │
│  └─ settings.json - Claude Code settings                   │
└─────────────────────────────────────────────────────────────┘
```

### Authentication Flow

```
┌──────────────┐
│ entrypoint.sh│
└──────┬───────┘
       │
       ├─> Check Google Cloud ADC credentials
       │   └─> If missing: gcloud auth application-default login
       │   └─> Set project: ANTHROPIC_VERTEX_PROJECT_ID
       │   └─> Set quota: ANTHROPIC_VERTEX_PROJECT_QUOTA
       │
       ├─> Load custom commands from /workspace/.claude/commands/
       │   └─> Copy *.md files to ~/.claude/commands/
       │
       ├─> Load context from ~/.claude/context.d/*.md
       │   └─> Concatenate into single context file
       │
       └─> Launch Claude Code with:
           ├─ Pre-loaded context (--session-id)
           ├─ MCP configurations from ~/.claude/mcp.d/*.json
           └─> Claude Code → Vertex AI API (us-east5)
```

## Directory Structure

```
/workspace/
├── Containerfile              # Multi-arch container image definition
├── entrypoint.sh              # Startup script: auth + Claude launch
├── Makefile                   # Build/push automation
├── README.md                  # User-facing documentation
├── renovate.json              # Automated dependency updates
├── conf/
│   ├── .claude.json          # Claude Code initial state
│   └── .claude/
│       ├── context.d/
│       │   └── CLAUDE-base.md    # Sequential thinking memory + MCP usage
│       ├── mcp.d/
│       │   └── mcp-base.json     # Slack, GitLab, K8s MCP configs
│       └── settings.json         # Permissions whitelist
└── .github/
    └── workflows/
        └── build.yml          # Multi-arch CI/CD pipeline
```

## MCP Server Integrations

### 1. Slack MCP Server

**Purpose**: Enable Claude Code to read/search/post messages to Slack channels

**Key Tools Available**:
- `mcp__slack__conversations_history` - Read channel history
- `mcp__slack__channels_list` - List available channels
- `mcp__slack__conversations_search_messages` - Search messages
- `mcp__slack__conversations_add_message` - Post messages

**Authentication**: Enterprise Slack via XOXC/XOXD tokens (extracted from browser)

**Use Cases**:
- Monitor release announcements in `#forum-rhaiis-release`
- Track dependency updates in `#forum-aipcc-wheels`
- Post automation status updates
- Search historical context for debugging

**Configuration Location**: `conf/.claude/mcp.d/mcp-base.json:3-19`

### 2. GitLab MCP Server

**Purpose**: Interact with GitLab CI/CD pipelines, merge requests, and jobs

**Key Tools Available**:
- `mcp__gitlab__list_project_merge_requests` - List MRs for projects
- `mcp__gitlab__get_merge_request` - Get MR details
- `mcp__gitlab__get_job` - Fetch CI job logs/status
- `mcp__gitlab__list_group_merge_requests` - List group-wide MRs

**Authentication**: Personal Access Token (PAT) via `GITLAB_TOKEN`

**Use Cases**:
- Monitor RHAIIS container builds (Project ID: 68845382)
- Fetch pipeline failure logs
- Review merge request status
- Automate release tag verification

**Configuration Location**: `conf/.claude/mcp.d/mcp-base.json:21-27`

### 3. Kubernetes MCP Server

**Purpose**: Query and manage Kubernetes/OpenShift resources

**Key Tools Available**:
- `mcp__k8s__resources_list` - List resources (Pods, Deployments, Releases, etc.)
- `mcp__k8s__resources_get` - Get resource details (YAML specs, status, etc.)

**Safety**: Runs in `--disable-destructive` mode (read-only by default)

**Authentication**: Kubeconfig file mounted at runtime via `K8S_MCP_KUBECONFIG_PATH`

**Use Cases**:
- Query Konflux Releases in `ai-tenant` namespace
- Monitor PipelineRun status
- Extract snapshot IDs from Release resources
- Verify ReleasePlan configurations

**Configuration Location**: `conf/.claude/mcp.d/mcp-base.json:28-39`

## Custom Commands

Claudio supports loading project-specific **slash commands** from your workspace at runtime. This enables teams to create reusable command templates for common workflows.

### How It Works

1. **Create commands directory** in your workspace:
   ```bash
   mkdir -p /workspace/.claude/commands
   ```

2. **Add command files** (Markdown format with `.md` extension):
   ```bash
   cat > /workspace/.claude/commands/create-release.md << 'EOF'
   # Create RHAIIS Release

   Create production Release YAMLs for RHAIIS version $1.

   Steps:
   1. Find Git SHA for tag v$1
   2. List all stage releases for that SHA
   3. Extract snapshot IDs
   4. Generate 5 production Release YAML files
   EOF
   ```

3. **Mount workspace** when running Claudio:
   ```bash
   podman run -it --rm --user 0 \
     -v ${PWD}:/workspace:z \
     -v ${PWD}/kubeconfig:/opt/k8s/kubeconfig:z \
     -e ANTHROPIC_VERTEX_PROJECT_ID='my-project' \
     -e ANTHROPIC_VERTEX_PROJECT_QUOTA='my-project' \
     -e K8S_MCP_KUBECONFIG_PATH=/opt/k8s/kubeconfig \
     quay.io/redhat-aipcc/claudio:v1.0.0-dev
   ```

4. **Use the command** in Claude Code session:
   ```
   /create-release 3.2.2
   ```

### Running Commands Non-Interactively

You can execute slash commands directly when starting the container by passing them as arguments:

```bash
# Execute a custom slash command
podman run -it --rm --user 0 \
  -v ${PWD}:/workspace:z \
  -v ${PWD}/kubeconfig:/opt/k8s/kubeconfig:z \
  -e ANTHROPIC_VERTEX_PROJECT_ID='my-project' \
  -e ANTHROPIC_VERTEX_PROJECT_QUOTA='my-project' \
  -e K8S_MCP_KUBECONFIG_PATH=/opt/k8s/kubeconfig \
  quay.io/redhat-aipcc/claudio:v1.0.0-dev \
  /create-release 3.2.3

# Execute troubleshooting command with project ID
podman run -it --rm --user 0 \
  -v ${PWD}:/workspace:z \
  -e GITLAB_URL='https://gitlab.com' \
  -e GITLAB_TOKEN='glpat-...' \
  -e ANTHROPIC_VERTEX_PROJECT_ID='my-project' \
  -e ANTHROPIC_VERTEX_PROJECT_QUOTA='my-project' \
  quay.io/redhat-aipcc/claudio:v1.0.0-dev \
  /troubleshoot-pipeline 68845382
```

**How It Works**:
- Commands are loaded from `/workspace/.claude/commands/` at startup
- Context is pre-loaded into the session
- The slash command and its arguments are passed to `claude -r SESSION_ID`
- Claude executes the command automatically and exits

### Command Features

**Arguments**:
- `$ARGUMENTS` - All arguments as a single string
- `$1`, `$2`, `$3`, etc. - Individual positional arguments

**Example: Troubleshoot Pipeline**

```markdown
# Troubleshoot GitLab Pipeline

Diagnose and fix GitLab pipeline failures for project $1.

Steps:
1. List recent pipeline failures using GitLab MCP
2. Fetch logs for the most recent failed job
3. Analyze error messages
4. Suggest fixes based on common failure patterns
5. If applicable, propose a fix commit
```

**Usage**: `/troubleshoot-pipeline 68845382`

### Advanced Command Features

Commands support **frontmatter** for additional configuration:

```markdown
---
description: "Create RHAIIS production releases"
allowed_tools:
  - mcp__k8s__resources_list
  - mcp__k8s__resources_get
  - mcp__gitlab__get_merge_request
---

# Create RHAIIS Release

Create production Release YAMLs for RHAIIS version $1...
```

### Command Discovery

When Claudio starts, it:
1. Checks for `/workspace/.claude/commands/` directory
2. Copies all `*.md` files to `~/.claude/commands/`
3. Logs each loaded command: `Loading command: create-release`

**Note**: Commands are loaded at container startup. To add new commands, restart the container or manually copy them to `~/.claude/commands/` during the session.

## Base Context Memory

The file `conf/.claude/context.d/CLAUDE-base.md` contains sequential thinking guidelines that are injected into every Claude Code session:

**Key Directives**:
1. Use `skopeo` for container image inspection
2. Use MCP servers for K8s, Slack, and GitLab interactions
3. Summarize reasoning and list assumptions before final answers
4. Outline approach → show code → explain pitfalls when coding
5. Build incrementally, propose alternatives, ask clarifying questions
6. Regular checkpoints to summarize progress

**Why This Matters**: This ensures Claude Code consistently follows operational best practices and uses the correct tools for enterprise workflows.

## Required Environment Variables

### Google Vertex AI (Required)
```bash
ANTHROPIC_VERTEX_PROJECT_ID       # GCP project for Vertex AI API
ANTHROPIC_VERTEX_PROJECT_QUOTA    # Quota project (can be same as PROJECT_ID)
```

### Slack Integration (Optional)
```bash
SLACK_MCP_XOXC_TOKEN             # Workspace token (from browser localStorage)
SLACK_MCP_XOXD_TOKEN             # Session cookie (from browser cookies)
SLACK_MCP_USER_AGENT             # Browser User-Agent string
```

### GitLab Integration (Optional)
```bash
GITLAB_URL                       # GitLab instance URL (e.g., https://gitlab.com)
GITLAB_TOKEN                     # Personal Access Token with API scope
```

### Kubernetes Integration (Optional)
```bash
K8S_MCP_KUBECONFIG_PATH          # Path to kubeconfig file (mounted volume)
```

### Debug (Optional)
```bash
DEBUG=true                       # Enable shell debugging in entrypoint.sh
```

## Build Process

### Local Build (Native Architecture)

```bash
# Default: Podman, quay.io/redhat-aipcc/claudio:v1.0.0-dev
make oci-build

# Custom image/tag
IMAGE_REPO=ghcr.io/myorg/claudio IMAGE_TAG=latest make oci-build

# Using Docker
CONTAINER_MANAGER=docker make oci-build
```

### Multi-Architecture Build (CI/CD)

The GitHub Actions workflow (`.github/workflows/build.yml`) builds for both amd64 and arm64:

1. **Build Stage**: Parallel builds on `ubuntu-24.04` (amd64) and `ubuntu-24.04-arm` (arm64)
2. **Manifest Stage**: Creates multi-arch manifest and tags as `latest` on main branch

**Output Images**:
- `ghcr.io/{repo}:{sha}-amd64`
- `ghcr.io/{repo}:{sha}-arm64`
- `ghcr.io/{repo}:{sha}` (manifest referencing both)
- `ghcr.io/{repo}:latest` (main branch only)

## Runtime Usage

### Interactive Session (Full Features)

```bash
podman run -it --rm --user 0 \
  -v ${PWD}/kubeconfig:/opt/k8s/kubeconfig:z \
  -v claudio-gcp:/root/.config/gcloud:Z \
  -v claudio-mcp-slack:/root/claude/mcp/slack:Z \
  -e GITLAB_URL='https://gitlab.com' \
  -e GITLAB_TOKEN='glpat-...' \
  -e ANTHROPIC_VERTEX_PROJECT_ID='my-project' \
  -e ANTHROPIC_VERTEX_PROJECT_QUOTA='my-project' \
  -e SLACK_MCP_XOXC_TOKEN='xoxc-...' \
  -e SLACK_MCP_XOXD_TOKEN='xoxd-...' \
  -e K8S_MCP_KUBECONFIG_PATH=/opt/k8s/kubeconfig \
  quay.io/redhat-aipcc/claudio:v1.0.0-dev
```

### One-Time Prompt (Non-Interactive)

```bash
podman run -it --rm --user 0 \
  -v ${PWD}/kubeconfig:/opt/k8s/kubeconfig:z \
  -e GITLAB_URL='https://gitlab.com' \
  -e GITLAB_TOKEN='glpat-...' \
  -e ANTHROPIC_VERTEX_PROJECT_ID='my-project' \
  -e ANTHROPIC_VERTEX_PROJECT_QUOTA='my-project' \
  -e K8S_MCP_KUBECONFIG_PATH=/opt/k8s/kubeconfig \
  quay.io/redhat-aipcc/claudio:v1.0.0-dev \
  -p "List all Releases in ai-tenant namespace for RHAIIS 3.2.2"
```

## Volume Persistence

### Recommended Volumes

```bash
# Google Cloud credentials (survives container restarts)
podman volume create claudio-gcp

# Slack MCP cache (user/channel listings)
podman volume create claudio-mcp-slack
```

### Volume Purposes

| Volume | Path | Purpose |
|--------|------|---------|
| `claudio-gcp` | `/root/.config/gcloud` | Google Cloud ADC tokens |
| `claudio-mcp-slack` | `/root/claude/mcp/slack` | Slack user/channel cache |
| `kubeconfig` | `/opt/k8s/kubeconfig` | Kubernetes cluster credentials |

## OpenShift Compatibility

**User Configuration**:
- Default user: `default` (UID dynamically assigned by OpenShift)
- Group: `root` (GID 0) for volume access
- Entrypoint runs as UID 0 locally (`--user 0`) to avoid Podman volume permission issues

**Why This Works**:
- OpenShift assigns arbitrary UIDs but always includes GID 0
- `chown -R default:0` ensures group ownership
- `chmod -R ug+rwx` grants read/write to user and group

## Dependency Management

### Renovate Configuration

The `renovate.json` file auto-updates 5 critical dependencies:

| Dependency | Type | Datasource | Update Frequency |
|------------|------|------------|------------------|
| Claude Code CLI | NPM | `@anthropic-ai/claude-code` | Weekly |
| Google Cloud SDK | Docker | `google/cloud-sdk` | Weekly |
| Slack MCP Server | GitHub Releases | `korotovsky/slack-mcp-server` | Weekly |
| GitLab MCP | GitLab Releases | `fforster/gitlab-mcp` | Weekly |
| Kubernetes MCP | GitHub Releases | `containers/kubernetes-mcp-server` | Weekly |

**How It Works**:
1. Renovate scans `Containerfile` for `ENV *_V <version>` patterns
2. Checks upstream sources for new releases
3. Opens PRs with version bumps
4. GitHub Actions builds and tests automatically

## Common Workflows

### 1. RHAIIS Release Management

**Scenario**: Create production Release resources for RHAIIS 3.2.3

**Steps**:
1. Launch Claudio with K8s and GitLab MCP servers
2. Ask: "Find the Git SHA for tag v3.2.3-2025101502"
   - Uses `mcp__gitlab__get_merge_request` or K8s Release annotations
3. Ask: "List all stage releases for SHA abc123d"
   - Uses `mcp__k8s__resources_list` to find Releases
4. Ask: "Extract snapshot IDs from these releases"
   - Uses `mcp__k8s__resources_get` to read `spec.snapshot`
5. Ask: "Generate production Release YAMLs"
   - Claude generates 5 YAML files using the guide context
6. Apply YAMLs: `kubectl apply -f rhaiis-*.yaml`

### 2. CI/CD Troubleshooting

**Scenario**: Diagnose why a GitLab pipeline failed

**Steps**:
1. Ask: "Show me recent pipeline failures for project 68845382"
   - Uses `mcp__gitlab__list_project_merge_requests`
2. Ask: "Get logs for job ID 12345"
   - Uses `mcp__gitlab__get_job`
3. Ask: "Summarize the error and suggest a fix"
   - Claude analyzes logs and provides recommendations

### 3. Slack Release Coordination

**Scenario**: Track release status across Slack channels

**Steps**:
1. Ask: "Search for messages about v3.2.3 in #forum-rhaiis-release"
   - Uses `mcp__slack__conversations_search_messages`
2. Ask: "Summarize the release status"
   - Claude aggregates information from multiple messages
3. Ask: "Post an update that prod releases are complete"
   - Uses `mcp__slack__conversations_add_message`

## Operational Considerations

### Session Management

**Session Persistence**: Claude Code sessions are ephemeral by default. The entrypoint script:
1. Creates a session ID: `SESSIONID=$(uuidgen)`
2. Loads context: `claude -p "$(cat context.md)" --session-id $SESSIONID`
3. Resumes session: `claude -r $SESSIONID --mcp-config ...`

**Workaround for Issue #2425**: Due to a Claude Code bug, context must be pre-loaded in a separate command before resuming the session.

### Cost Management

**Vertex AI Quota**: Set `ANTHROPIC_VERTEX_PROJECT_QUOTA` to a separate project to track/limit API usage.

**Model**: Claudio uses `claude-sonnet-4-5@20250929` via Vertex AI (as of Claude Code v2.0.14).

### Security Best Practices

1. **Secrets Management**:
   - Use Kubernetes Secrets for environment variables in production
   - Never commit tokens to Git
   - Rotate Slack tokens when they expire (usually 90 days)

2. **Least Privilege**:
   - K8s MCP runs with `--disable-destructive` by default
   - Claude Code permissions whitelist in `conf/.claude/settings.json`
   - Only approve required MCP tools

3. **Network Isolation**:
   - Claudio requires outbound HTTPS to:
     - `generativelanguage.googleapis.com` (Vertex AI)
     - `slack.com` (Slack API)
     - `gitlab.com` (GitLab API)
     - Kubernetes API server (cluster-specific)

## Troubleshooting

### Authentication Issues

**Problem**: `gcloud auth application-default login` fails in container

**Solution**: Pre-authenticate on host and mount credentials:
```bash
gcloud auth application-default login
podman run -v ~/.config/gcloud:/root/.config/gcloud:z ...
```

### Slack Token Expiration

**Problem**: "invalid_auth" errors from Slack MCP

**Solution**:
1. Re-extract XOXC/XOXD from browser (see README.md:19-23)
2. First login after extraction will sign you out (security measure)
3. Second login should persist tokens

### K8s Permission Denied

**Problem**: "Forbidden" errors when querying Konflux

**Solution**: Verify kubeconfig has correct RBAC:
```bash
kubectl auth can-i list releases -n ai-tenant
```

### Volume Permission Errors

**Problem**: "Permission denied" when writing to mounted volumes

**Solution**: Run with `--user 0` locally or use `:Z` mount flag:
```bash
podman run --user 0 -v claudio-gcp:/root/.config/gcloud:Z ...
```

## Contributing

### Adding New MCP Servers

1. **Update Containerfile**: Add installation steps (see Slack/GitLab/K8s examples)
2. **Update mcp-base.json**: Add server configuration block
3. **Update settings.json**: Whitelist required tools in `permissions.allow`
4. **Update renovate.json**: Add version tracking regex if applicable
5. **Test**: Build container and verify MCP server loads

### Adding Custom Commands

Create `.md` files in `/workspace/.claude/commands/` and mount your workspace when running Claudio. Commands are automatically loaded at startup.

**Example structure**:
```
/workspace/
├── .claude/
│   └── commands/
│       ├── create-release.md
│       ├── troubleshoot-pipeline.md
│       └── security-review.md
```

**Usage in container**:
```bash
podman run -it --rm --user 0 \
  -v ${PWD}:/workspace:z \
  ...
  quay.io/redhat-aipcc/claudio:v1.0.0-dev
```

### Updating Base Context

Edit `conf/.claude/context.d/CLAUDE-base.md` to add new operational guidelines. Context files are concatenated alphabetically, so use prefixes (e.g., `00-memory.md`, `10-rhaiis.md`) to control load order.

## Related Projects

- **Claude Code**: https://github.com/anthropics/claude-code
- **Slack MCP Server**: https://github.com/korotovsky/slack-mcp-server
- **GitLab MCP**: https://gitlab.com/fforster/gitlab-mcp
- **Kubernetes MCP**: https://github.com/containers/kubernetes-mcp-server
- **RHAIIS Containers**: https://gitlab.com/redhat/rhel-ai/rhaiis/containers
- **Konflux**: https://konflux-ui.apps.stone-prod-p02.hjvn.p1.openshiftapps.com

## License

Apache License 2.0 - See `LICENSE` file for details.

## Maintainers

Red Hat AI/CC Platform Engineering Team

**Support Channels**:
- Issues: GitHub Issues (this repository)
- Slack: `#forum-aipcc-claudio` (internal Red Hat Slack)
