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
FROM registry.access.redhat.com/ubi10@sha256:0e04460ccf1ad68374b2f1ca28f8539f817fe8bb6107478df445e05dccb1995e as preparer
ARG TARGETARCH

RUN dnf install -y git 


# GCloud
ENV GCLOUD_V 573.0.0
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
RUN echo "cs-cache-key: ${CS_CACHE_KEY}" \
 && set -eux; \
    if [ "${CS_REF_TYPE}" = "pr" ]; then \
        git clone "${CS_REPO}"; \
        git -C claudio-skills fetch --depth 1 origin "pull/${CS_REF}/head"; \
        git -C claudio-skills checkout FETCH_HEAD; \
    fi; \
    mkdir -p claudio-skills;

# Claudio image    
FROM registry.access.redhat.com/ubi10/python-312-minimal@sha256:3707d38fb29c496d184e85b63a9ec2d1678bcb5086e5dab00540d6eeaa7951a7

ARG TARGETARCH
USER root
ENV HOME /home/claudio
ENV PATH="${HOME}/.local/bin:${PATH}"

# Base for claudio image
# pyopenssl is pulled in transitively by the UBI10 base image and is not a direct
# dependency. CVE-2026-27459 (CRITICAL) affects <26.0.0; pin the fixed version.
RUN microdnf install -y skopeo podman unzip gzip git jq && microdnf clean all; \
    pip install --no-cache-dir "pyopenssl>=26.0.0"; \
    useradd claudio 
    
# Claude
# https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md
ENV CLAUDE_V 2.1.179
ENV CLAUDE_CODE_USE_VERTEX=1 \
    CLOUD_ML_REGION=global \
    ANTHROPIC_DEFAULT_HAIKU_MODEL=claude-haiku-4-5@20251001 \
    DISABLE_AUTOUPDATER=1
ENV CLAUDE_BASE_URL="https://github.com/anthropics/claude-code/releases/download/v${CLAUDE_V}/claude-code-v${CLAUDE_V}"
RUN curl -fsSL https://claude.ai/install.sh | bash -s ${CLAUDE_V}
    
# GCloud
COPY --from=preparer /opt/google-cloud-sdk /opt/google-cloud-sdk
RUN set -eux; \
    /opt/google-cloud-sdk/install.sh -q; \
    ln -s /opt/google-cloud-sdk/bin/gcloud /usr/local/bin/gcloud; 

# Conf
COPY conf/ ${HOME}/
COPY scripts/ entrypoint.sh /usr/local/bin/

# Claudio Skills
COPY --from=preparer /claudio-skills /home/claudio/claudio-skills
ARG CS_REF_TYPE
ARG CS_REF
ARG CS_CACHE_KEY
RUN echo "cs-cache-key: ${CS_CACHE_KEY}" \
 && if [ "${CS_REF_TYPE}" = "pr" ]; then \
        claude plugin marketplace add /home/claudio/claudio-skills; \
    else \
        claude plugin marketplace add aipcc-cicd/claudio-skills@${CS_REF}; \
    fi; \
    claude plugin install --scope user claudio-plugin; \
    pt-manager.sh


# MemPalace
ENV MEMPALACE_V 3.4.1
ENV MEMPAL_SAVE_INTERVAL 5
RUN pip install --no-cache-dir MemPalace==${MEMPALACE_V}; \
    claude plugin marketplace add MemPalace/mempalace@v${MEMPALACE_V};\
    claude plugin install --scope user mempalace; \
    grep -q '^SAVE_INTERVAL=[0-9]' ${HOME}/.claude/plugins/marketplaces/mempalace/hooks/mempal_save_hook.sh || \
        { echo 'ERROR: SAVE_INTERVAL pattern not found in hook script'; exit 1; }; \         
    sed -i 's/^SAVE_INTERVAL=[0-9]\+/SAVE_INTERVAL="${MEMPAL_SAVE_INTERVAL:-15}"/' ${HOME}/.claude/plugins/marketplaces/mempalace/hooks/mempal_save_hook.sh;

# Claudio
RUN chown -R claudio:0 ${HOME}; \
    chmod -R ug+rwx ${HOME}
USER claudio
WORKDIR /home/claudio

# Entrypoint
ENTRYPOINT ["entrypoint.sh"]
