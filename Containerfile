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
FROM registry.access.redhat.com/ubi10@sha256:a2ad0aa42a07c5fd4d9fd440b4c968e2c696d4b40c2018a44eedd8c156fd4143 as preparer
ARG TARGETARCH

RUN dnf install -y git 


# GCloud
ENV GCLOUD_V 565.0.0
ENV GCLOUD_BASE_URL="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${GCLOUD_V}"
ENV GCLOUD_URL="${GCLOUD_BASE_URL}-linux-x86_64.tar.gz"
RUN set -eux; \
    if [ "$TARGETARCH" = "arm64" ]; then \
        export GCLOUD_URL="${GCLOUD_BASE_URL}-linux-arm.tar.gz"; \
    fi; \
    curl -L "$GCLOUD_URL" -o gcloud.tar.gz; \
    tar -xzf gcloud.tar.gz -C /opt;

# Claudio Skills
ARG CS_REF_TYPE
ARG CS_REF
# CS_CACHE_KEY is the resolved commit SHA — changing it invalidates the layer
# cache so we always get fresh content when the remote ref updates.
ARG CS_CACHE_KEY
ENV CS_REPO https://github.com/aipcc-cicd/claudio-skills.git
RUN set -eux; \
    git init claudio-skills; \
    cd claudio-skills; \
    git remote add origin "${CS_REPO}"; \
    if [ "${CS_REF_TYPE}" = "pr" ]; then \
        git fetch --depth 1 origin "pull/${CS_REF}/head"; \
    else \
        git fetch --depth 1 origin "${CS_REF}"; \
    fi; \
    git checkout FETCH_HEAD;

# Claudio image    
FROM registry.access.redhat.com/ubi10/python-312-minimal@sha256:df10cfea920731d904d38bbe1b720d866286611a849f590c9281083b860764ec

ARG TARGETARCH
USER root


ENV HOME /home/claudio

# Base for claudio image
RUN microdnf install -y skopeo podman unzip gzip git; \
    useradd claudio 
    
# Claude
# https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md
ENV CLAUDE_V 2.1.116
ENV CLAUDE_CODE_USE_VERTEX=1 \
    CLOUD_ML_REGION=us-east5 \
    ANTHROPIC_DEFAULT_HAIKU_MODEL=claude-haiku-4-5@20251001 \
    DISABLE_AUTOUPDATER=1
ENV CLAUDE_BASE_URL="https://github.com/anthropics/claude-code/releases/download/v${CLAUDE_V}/claude-code-v${CLAUDE_V}"
RUN curl -fsSL https://claude.ai/install.sh | bash -s ${CLAUDE_V} && \
    ln -s ~/.local/bin/claude /usr/local/bin/claude
    
# GCloud
COPY --from=preparer /opt/google-cloud-sdk /opt/google-cloud-sdk
RUN set -eux; \
    /opt/google-cloud-sdk/install.sh -q; \
    ln -s /opt/google-cloud-sdk/bin/gcloud /usr/local/bin/gcloud; 

# Conf
COPY conf/ ${HOME}/
COPY scripts/ /usr/local/bin/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Skills
COPY --from=preparer /claudio-skills /home/claudio/claudio-skills
RUN set -eux; \
    for script in "${HOME}/claudio-skills"/claudio-plugin/tools/*/install.sh; do \
        [ -f "$script" ] && bash "$script"; \
    done; \
    \
    for req in "${HOME}/claudio-skills"/claudio-plugin/tools/python/*-requirements.txt; do \
        [ -f "$req" ] && pip install --no-cache-dir -r "$req"; \
    done; \
    \
    /usr/local/bin/generate-plugin-configs.sh \
        "${HOME}/claudio-skills" \
        "${HOME}/.claude/plugins"

# Claudio
RUN chown -R claudio:0 ${HOME}; \
    chmod -R ug+rwx ${HOME}
USER claudio
WORKDIR /home/claudio

# Entrypoint
ENTRYPOINT ["entrypoint.sh"]
