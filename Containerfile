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
FROM registry.access.redhat.com/ubi10@sha256:9d3b5102e7ae4f82914a1791610b75acef134b93158be6005b6ae9218c163550 as preparer
ARG TARGETARCH

RUN dnf install -y git 


# GCloud
ENV GCLOUD_V 566.0.0
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
FROM registry.access.redhat.com/ubi10/python-312-minimal@sha256:1124c0e91dbae9b8893a218e34e7437b03865da333015078fd6bb84e2daf3665

ARG TARGETARCH
USER root
ENV HOME /home/claudio
ENV PATH="${HOME}/.local/bin:${PATH}"

# Base for claudio image
RUN microdnf install -y skopeo podman unzip gzip git jq; \
    useradd claudio 
    
# Claude
# https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md
ENV CLAUDE_V 2.1.126
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

# Claudio
RUN chown -R claudio:0 ${HOME}; \
    chmod -R ug+rwx ${HOME}
USER claudio
WORKDIR /home/claudio

# Entrypoint
ENTRYPOINT ["entrypoint.sh"]
