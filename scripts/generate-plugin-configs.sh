#!/bin/bash
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

set -e

MARKETPLACE_DIR="${1:-/home/default/claudio-skills}"
CONFIG_DIR="${2:-/home/default/.claude/plugins}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

# Read marketplace metadata
MARKETPLACE_JSON="${MARKETPLACE_DIR}/.claude-plugin/marketplace.json"
if [ ! -f "$MARKETPLACE_JSON" ]; then
    echo "Error: Marketplace metadata not found at $MARKETPLACE_JSON"
    exit 1
fi

MARKETPLACE_NAME=$(jq -r '.name' "$MARKETPLACE_JSON")

# Build installed_plugins.json using process substitution to avoid subshell issues
INSTALLED_PLUGINS='{"version":1,"plugins":{}}'

while IFS= read -r plugin_source; do
    plugin_name=$(echo "$plugin_source" | jq -r '.name')
    plugin_path=$(echo "$plugin_source" | jq -r '.source')

    # Read plugin metadata
    plugin_json="${MARKETPLACE_DIR}/${plugin_path}/.claude-plugin/plugin.json"
    if [ ! -f "$plugin_json" ]; then
        echo "Warning: Plugin metadata not found at $plugin_json, skipping..."
        continue
    fi

    plugin_version=$(jq -r '.version' "$plugin_json")
    plugin_install_path="${MARKETPLACE_DIR}/${plugin_path}"
    plugin_key="${plugin_name}@${MARKETPLACE_NAME}"

    # Add to installed_plugins
    INSTALLED_PLUGINS=$(echo "$INSTALLED_PLUGINS" | jq \
        --arg key "$plugin_key" \
        --arg version "$plugin_version" \
        --arg timestamp "$TIMESTAMP" \
        --arg path "$plugin_install_path" \
        '.plugins[$key] = {
            "version": $version,
            "installedAt": $timestamp,
            "lastUpdated": $timestamp,
            "installPath": $path,
            "isLocal": true
        }')
done < <(jq -c '.plugins[]' "$MARKETPLACE_JSON")

# Build known_marketplaces.json
KNOWN_MARKETPLACES=$(jq -n \
    --arg name "$MARKETPLACE_NAME" \
    --arg path "$MARKETPLACE_DIR" \
    --arg timestamp "$TIMESTAMP" \
    '{
        ($name): {
            "source": {
                "source": "directory",
                "path": $path
            },
            "installLocation": $path,
            "lastUpdated": $timestamp
        }
    }')

# Ensure config directory exists
mkdir -p "$CONFIG_DIR"

# Write config files
echo "$INSTALLED_PLUGINS" | jq '.' > "${CONFIG_DIR}/installed_plugins.json"
echo "$KNOWN_MARKETPLACES" | jq '.' > "${CONFIG_DIR}/known_marketplaces.json"

echo "Generated plugin configs in ${CONFIG_DIR}"
echo "- Installed plugins: $(echo "$INSTALLED_PLUGINS" | jq -r '.plugins | keys | length') plugin(s)"
echo "- Known marketplaces: ${MARKETPLACE_NAME}"
