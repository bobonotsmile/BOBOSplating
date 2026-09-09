#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")"
source publish-config/release-common.sh
docker compose run --rm --no-deps splat-backend nvidia-smi
report=$(docker compose run --rm --no-deps splat-backend vulkaninfo --summary)
printf '%s\n' "$report"
printf '%s\n' "$report" | grep -Eiq 'deviceName.*NVIDIA' || { echo 'No NVIDIA Vulkan device found' >&2; exit 1; }
docker compose run --rm --no-deps splat-backend brush_app --help >/dev/null
echo 'GPU visibility, NVIDIA Vulkan device and Brush CLI checked; real training is still required.'
