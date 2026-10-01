#!/usr/bin/env bash
# One-shot setup of a single-node Wazuh lab on macOS (Docker Desktop).
# - pins the official wazuh-docker release
# - turns on full event archiving (needed to hunt with the Sigma queries)
# - optionally adds the Microsoft 365 collector (lab/manager/office365.local.xml)
set -euo pipefail

WAZUH_VERSION="v4.14.8"
LAB_DIR="$(cd "$(dirname "$0")" && pwd)"
WD="$LAB_DIR/wazuh-docker/single-node"

say() { printf '\n==> %s\n' "$*"; }

command -v docker >/dev/null || { echo "Docker Desktop is required: https://www.docker.com/products/docker-desktop/"; exit 1; }

mem_bytes=$(docker info --format '{{.MemTotal}}')
if [ "$mem_bytes" -lt 7500000000 ]; then
  echo "WARNING: Docker Desktop has $((mem_bytes/1024/1024/1024)) GB RAM. Wazuh needs ~8 GB."
  echo "         Docker Desktop > Settings > Resources > Memory."
fi

say "Setting vm.max_map_count in the Docker VM (required by the indexer)"
docker run --rm --privileged alpine sysctl -w vm.max_map_count=262144 >/dev/null

if [ ! -d "$LAB_DIR/wazuh-docker" ]; then
  say "Cloning wazuh-docker $WAZUH_VERSION"
  git clone -q --depth 1 -b "$WAZUH_VERSION" https://github.com/wazuh/wazuh-docker.git "$LAB_DIR/wazuh-docker"
fi

CONF="$WD/config/wazuh_cluster/wazuh_manager.conf"
say "Enabling full event archiving (logall_json)"
perl -pi -e 's#<logall_json>no</logall_json>#<logall_json>yes</logall_json>#' "$CONF"

if [ -f "$LAB_DIR/manager/office365.local.xml" ] && ! grep -q "<office365>" "$CONF"; then
  say "Adding Microsoft 365 collector"
  cat "$LAB_DIR/manager/office365.local.xml" >> "$CONF"
fi

cd "$WD"
if [ ! -f config/wazuh_indexer_ssl_certs/root-ca.pem ]; then
  say "Generating TLS certificates"
  docker compose -f generate-indexer-certs.yml run --rm generator
fi

say "Starting Wazuh (first start takes a few minutes)"
docker compose up -d

say "Waiting for the manager container"
until docker compose exec -T wazuh.manager test -f /etc/filebeat/filebeat.yml 2>/dev/null; do sleep 5; done
sleep 20

if docker compose exec -T wazuh.manager grep -A1 'archives:' /etc/filebeat/filebeat.yml | grep -q 'enabled: false'; then
  say "Shipping archives to the indexer (wazuh-archives-*)"
  docker compose exec -T wazuh.manager sed -i '/archives:/{n;s/enabled: false/enabled: true/}' /etc/filebeat/filebeat.yml
  docker compose restart wazuh.manager
fi

cat <<MSG

Wazuh is starting. In 2-3 minutes open:  https://localhost
  user: admin   password: SecretPassword   (lab only - change it before exposing anything)

Next steps: lab/README.md, section 3 (Windows VM + agent).
MSG
