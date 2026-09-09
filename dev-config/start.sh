#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")"
source publish-config/release-common.sh
while IFS= read -r port; do
    if ss -H -ltn "sport = :$port" | grep -q .; then
        echo "Port $port is already listening. Stop this deployment before updating, or choose a free port." >&2
        exit 1
    fi
done < <(cfg --ports)
bash check-gpu.sh
docker compose up -d --no-build --pull never --wait --wait-timeout 120
bash check-services.sh
