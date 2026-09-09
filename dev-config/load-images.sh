#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")"
source publish-config/release-common.sh
(cd images && sha256sum -c SHA256SUMS)
docker load -i images/bobosplating-linux-amd64.tar.gz
for image in "$(cfg BOBO_BACKEND_IMAGE)" "$(cfg BOBO_FRONTEND_IMAGE)"; do
    [[ $(docker image inspect "$image" --format '{{.Os}}/{{.Architecture}}') == linux/amd64 ]] || exit 1
done
echo 'Application images loaded and architecture checked.'
