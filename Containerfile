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

FROM registry.access.redhat.com/ubi10/nodejs-22@sha256:11339a3f4cc8163571306eff86b038240c2fd3e307bce317ee06f1ce45814fbd

ARG TARGETARCH
USER root
ENV HOME /home/default

# Basic tools
RUN dnf install -y skopeo podman jq 

# Claude
# https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md
ENV CLAUDE_V 2.0.37
ENV CLAUDE_CODE_USE_VERTEX=1 \
    CLOUD_ML_REGION=us-east5 \
    DISABLE_AUTOUPDATER=1
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_V} 

# GCloud
ENV GCLOUD_V 547.0.0
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

# Gitlab
# https://github.com/zereight/gitlab-mcp/releases
ENV GITLAB_MCP_V 2.0.11

# K8s
# https://github.com/containers/kubernetes-mcp-server/releases
ENV K8S_MCP_V v0.0.54

# Conf
COPY conf/ ${HOME}/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Setup non root user
WORKDIR /home/default
RUN chown -R default:0 ${HOME} && \
    chmod -R ug+rwx ${HOME}
USER default

# Entrypoint
ENTRYPOINT ["entrypoint.sh"]
