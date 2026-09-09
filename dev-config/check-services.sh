#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")"
source publish-config/release-common.sh
docker compose ps
for service in splat-backend web-frontend; do
    id=$(docker compose ps -q "$service")
    [[ -n "$id" ]] || { echo "$service not running" >&2; exit 1; }
    [[ $(docker inspect "$id" --format '{{.State.Health.Status}}') == healthy ]] || { echo "$service unhealthy" >&2; exit 1; }
done
docker compose exec -T splat-backend sh -c 'test "$Bobo__DataRoot" = /data && test -w /data && printf "%s\n" "$ASPNETCORE_URLS"'
host=$(cfg BOBO_PUBLIC_HOST)
port=$(cfg BOBO_HTTPS_PORT)
bind_ip=$(cfg BOBO_BIND_IP)
[[ "$bind_ip" != 0.0.0.0 ]] || bind_ip=127.0.0.1
base="https://$host:$port"
curl_args=(--fail --silent --show-error --noproxy '*' --cacert publish-config/certs/server.crt --resolve "$host:$port:$bind_ip")
curl "${curl_args[@]}" "$base/" >/dev/null
curl "${curl_args[@]}" "$base/api/health" | python3 -c 'import json,sys; assert json.load(sys.stdin)["status"] == "ok"'
curl "${curl_args[@]}" "$base/api/settings" | python3 -c 'import json,sys; s=json.load(sys.stdin); assert s["toolsReady"], s["missingTools"]'
echo 'Containers, data permissions, HTTPS hostname/certificate, frontend and API proxy checked.'
echo "Open $base in your browser and submit a quick reconstruction for final acceptance."
