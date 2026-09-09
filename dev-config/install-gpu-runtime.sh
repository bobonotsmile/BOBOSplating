#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")"
[[ $EUID == 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
[[ ${1:-} == --restart-docker ]] || {
    echo 'This installs NVIDIA Container Toolkit and restarts Docker, affecting existing containers.'
    echo 'Schedule downtime, then run: sudo bash install-gpu-runtime.sh --restart-docker'
    exit 1
}
[[ $(dpkg --print-architecture) == amd64 ]] || { echo 'Requires amd64' >&2; exit 1; }
# Do not silently downgrade a newer host installation.
for package in nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container1 libnvidia-container-tools; do
    installed=$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)
    if [[ -n "$installed" ]] && dpkg --compare-versions "$installed" gt 1.20.0-1; then
        echo "$package $installed is newer than this bundle; keep it and configure the existing runtime manually." >&2
        exit 1
    fi
done
(cd publish-config/nvidia-toolkit && sha256sum -c SHA256SUMS)
# Simulation catches missing Ubuntu prerequisites before making changes; no network downloads.
packages=("$PWD"/publish-config/nvidia-toolkit/*.deb)
apt-get --no-download --simulate install "${packages[@]}"
# apt --no-download can reject local debs even with absolute paths on Ubuntu 24.04.
# dpkg installs only these files and never downloads packages.
dpkg -i "${packages[@]}"
if [[ -f /etc/docker/daemon.json ]]; then
    cp -p /etc/docker/daemon.json "/etc/docker/daemon.json.bobo-backup-$(date +%Y%m%d%H%M%S)"
fi
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker
docker info --format '{{json .Runtimes}}' | python3 -c 'import sys,json; assert "nvidia" in json.load(sys.stdin), "NVIDIA runtime missing"'
echo 'NVIDIA runtime registered. Next run check-gpu.sh to verify container GPU access.'
