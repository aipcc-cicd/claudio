#
# Copyright (C) 2025 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0

FROM registry.access.redhat.com/ubi10/nodejs-22@sha256:2b23012dc0ad8deaa4a6a5dd87101a36240f264f201dc30ce663ab3fe14a1e1c

ARG TARGETARCH
USER root
ENV HOME /home/default

# Basic tools
RUN dnf install -y skopeo podman 

# Claude
# https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md
ENV CLAUDE_V 2.1.50
ENV CLAUDE_CODE_USE_VERTEX=1 \
    CLOUD_ML_REGION=us-east5 \
    DISABLE_AUTOUPDATER=1
ENV CLAUDE_BASE_URL="https://github.com/anthropics/claude-code/releases/download/v${CLAUDE_V}/claude-code-v${CLAUDE_V}"
RUN curl -fsSL https://claude.ai/install.sh | bash -s ${CLAUDE_V} && \
    ln -s ~/.local/bin/claude /usr/local/bin/claude
    

# GCloud
ENV GCLOUD_V 557.0.0
ENV GCLOUD_BASE_URL="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${GCLOUD_V}"
ENV GCLOUD_URL="${GCLOUD_BASE_URL}-linux-x86_64.tar.gz"
RUN set -eux; \
    if [ "$TARGETARCH" = "arm64" ]; then \
        export GCLOUD_URL="${GCLOUD_BASE_URL}-linux-arm.tar.gz"; \
    fi; \
    curl -L "$GCLOUD_URL" -o gcloud.tar.gz; \
    tar -xzf gcloud.tar.gz -C /opt; \
    /opt/google-cloud-sdk/install.sh -q; \
    ln -s /opt/google-cloud-sdk/bin/gcloud /usr/local/bin/gcloud; \
    rm gcloud.tar.gz

# Slack
# https://github.com/korotovsky/slack-mcp-server/releases
ENV SLACK_MCP_V v1.1.26
ENV SLACK_MCP_CUSTOM_TLS=1 \
    SLACK_MCP_USER_AGENT='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36' \
    SLACK_MCP_USERS_CACHE=${HOME}/claude/mcp/slack/.users_cache.json \
    SLACK_MCP_CHANNELS_CACHE=${HOME}/claude/mcp/slack/.channels_cache_v2.json

# Kubectl
# https://kubernetes.io/releases/
ENV KUBECTL_V 1.35.1
RUN curl -L https://dl.k8s.io/release/v${KUBECTL_V}/bin/linux/${TARGETARCH}/kubectl -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl


# Conf
COPY conf/ ${HOME}/
COPY scripts/ /usr/local/bin/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Claudio Skills
ARG CS_REF_TYPE
ARG CS_REF
ENV CS_REPO https://github.com/aipcc-cicd/claudio-skills.git
RUN set -eux; \
    git init "${HOME}/claudio-skills"; \
    cd "${HOME}/claudio-skills"; \
    \
    git remote add origin "${CS_REPO}"; \
    if [ "${CS_REF_TYPE}" = "pr" ]; then \
        git fetch --depth 1 origin "pull/${CS_REF}/head"; \
    else \
        git fetch --depth 1 origin "${CS_REF}"; \
    fi; \
    git checkout FETCH_HEAD; \
    \
    for script in "${HOME}/claudio-skills"/claudio-plugin/tools/*/install.sh; do \
        [ -f "$script" ] && bash "$script"; \
    done; \
    \
    /usr/local/bin/generate-plugin-configs.sh \
        "${HOME}/claudio-skills" \
        "${HOME}/.claude/plugins"


# Setup non root user
WORKDIR /home/default
RUN chown -R default:0 ${HOME} && \
    chmod -R ug+rwx ${HOME}
USER default

# Entrypoint
ENTRYPOINT ["entrypoint.sh"]
