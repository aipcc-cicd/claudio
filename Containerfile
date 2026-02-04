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

FROM registry.access.redhat.com/ubi10/nodejs-22@sha256:42478ccd19d23f2185d34fcec544cf6d91610955eec5c9300a7e2d5639cb2f42

ARG TARGETARCH
USER root
ENV HOME /home/default

# Basic tools
RUN dnf install -y skopeo podman jq 

# Claude
# https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md
ENV CLAUDE_V 2.1.31
ENV CLAUDE_CODE_USE_VERTEX=1 \
    CLOUD_ML_REGION=us-east5 \
    DISABLE_AUTOUPDATER=1
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_V} 

# GCloud
ENV GCLOUD_V 555.0.0
ENV GCLOUD_BASE_URL="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${GCLOUD_V}"
ENV GCLOUD_URL="${GCLOUD_BASE_URL}-linux-x86_64.tar.gz"
RUN if [ "$TARGETARCH" = "arm64" ]; then export GCLOUD_URL="${GCLOUD_BASE_URL}-linux-arm.tar.gz"; fi && \
    curl -L ${GCLOUD_URL} -o gcloud.tar.gz && \
    tar -xzf gcloud.tar.gz -C /opt && \
    /opt/google-cloud-sdk/install.sh -q && \
    ln -s /opt/google-cloud-sdk/bin/gcloud /usr/local/bin/gcloud && \
    rm gcloud.tar.gz 

# Slack
# https://github.com/korotovsky/slack-mcp-server/releases
ENV SLACK_MCP_V v1.1.26
ENV SLACK_MCP_CUSTOM_TLS=1 \
    SLACK_MCP_USER_AGENT='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36' \
    SLACK_MCP_USERS_CACHE=${HOME}/claude/mcp/slack/.users_cache.json \
    SLACK_MCP_CHANNELS_CACHE=${HOME}/claude/mcp/slack/.channels_cache_v2.json

# Glab CLI
# https://gitlab.com/gitlab-org/cli/-/releases
ENV GLAB_V 1.78.3
RUN curl -L https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_V}/downloads/glab_${GLAB_V}_linux_${TARGETARCH}.rpm -o glab.rpm && \
    dnf install -y ./glab.rpm && \
    rm glab.rpm

# Kubectl
# https://kubernetes.io/releases/
ENV KUBECTL_V 1.35.0
RUN curl -L https://dl.k8s.io/release/v${KUBECTL_V}/bin/linux/${TARGETARCH}/kubectl -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl

# Claudio Skills
# https://github.com/aipcc-cicd/claudio-skills/releases
ENV CLAUDIO_SKILLS_V v0.1.0

# Conf
COPY conf/ ${HOME}/
COPY scripts/ /usr/local/bin/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Clone the skills marketplace and generate plugin configs (as root)
RUN git clone --branch ${CLAUDIO_SKILLS_V} --depth 1 https://github.com/aipcc-cicd/claudio-skills.git ${HOME}/claudio-skills && \
    /usr/local/bin/generate-plugin-configs.sh ${HOME}/claudio-skills ${HOME}/.claude/plugins

# Setup non root user
WORKDIR /home/default
RUN chown -R default:0 ${HOME} && \
    chmod -R ug+rwx ${HOME}
USER default

# Entrypoint
ENTRYPOINT ["entrypoint.sh"]
