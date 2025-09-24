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

FROM registry.access.redhat.com/ubi10/nodejs-22@sha256:d7bf3dca100e1193a5b0ea49ae9c23b38738b56b95c65dcd0f601c0f8c8ab3b2

ARG TARGETARCH

USER root
ENV HOME /root

# Claude
# https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md
ENV CLAUDE_V 1.0.113
ENV CLAUDE_CODE_USE_VERTEX=1 \
    CLOUD_ML_REGION=us-east5 \
    DISABLE_AUTOUPDATER=1
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_V} 

# GCloud
ENV GCLOUD_V 538.0.0
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
ENV SLACK_MCP_V v1.1.24
ENV SLACK_MCP_CUSTOM_TLS=1 \
    SLACK_MCP_USER_AGENT='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36' \
    SLACK_MCP_USERS_CACHE=${HOME}/claude/mcp/slack/.users_cache.json \
    SLACK_MCP_CHANNELS_CACHE=${HOME}/claude/mcp/slack/.channels_cache_v2.json

# Gitlab
# https://gitlab.com/fforster/gitlab-mcp/-/releases 
ENV GITLAB_MCP_V 1.31.0
ENV GITLAB_MCP_BASE_URL https://gitlab.com/fforster/gitlab-mcp/-/releases/v${GITLAB_MCP_V}/downloads/gitlab-mcp_${GITLAB_MCP_V}
ENV GITLAB_MCP_URL ${GITLAB_MCP_BASE_URL}_Linux_x86_64.tar.gz
RUN mkdir -p ${HOME}/claude/mcp/slack && \
    if [ "$TARGETARCH" = "arm64" ]; then export GITLAB_MCP_URL="${GITLAB_MCP_BASE_URL}_Linux_arm64.tar.gz"; fi && \
    curl -L ${GITLAB_MCP_URL} -o gitlab-mcp.tar.gz && \
    tar -xzvf gitlab-mcp.tar.gz && \
    mv gitlab-mcp /usr/local/bin/ && \
    rm gitlab-mcp.tar.gz

# Conf
COPY conf/ ${HOME}/

# Entrypoint
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
