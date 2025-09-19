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

VERSION ?= 1.0.0-dev
CONTAINER_MANAGER ?= podman

# Image URL to use all building/pushing image targets
IMG ?= quay.io/redhat-aipcc/claudio:v${VERSION}

# Build actions
.PHONY: oci-build oci-build-amd64 oci-build-arm64 oci-manifest

oci-build: oci-build-amd64 oci-build-arm64 oci-manifest
 
oci-build-amd64: 
	${CONTAINER_MANAGER} build --platform linux/amd64 -t $(IMG)-amd64 -f Containerfile .

oci-build-arm64: 
	${CONTAINER_MANAGER} build --platform linux/arm64 -t $(IMG)-arm64 -f Containerfile .

oci-manifest:
	${CONTAINER_MANAGER} manifest create --amend $(IMG)
	${CONTAINER_MANAGER} manifest add --all $(IMG) containers-storage:$(IMG)-amd64
	${CONTAINER_MANAGER} manifest add --all $(IMG) containers-storage:$(IMG)-arm64
