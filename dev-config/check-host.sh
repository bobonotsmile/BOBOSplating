#!/usr/bin/env bash
# Read-only host inventory. Does not install, pull images, or start containers.
set -u

section() { printf '\n== %s ==\n' "$1"; }
section 'Operating system and architecture'
cat /etc/os-release
uname -m

section 'Memory and available disk space'
free -h
df -h . /opt

section 'Docker and Compose'
if ! command -v docker >/dev/null 2>&1; then
    printf 'Docker is not in PATH. No installation was attempted.\n' >&2
    exit 1
fi
docker version --format 'Client={{.Client.Version}} Server={{.Server.Version}}' || {
    printf 'Cannot access Docker. Run this read-only script with sudo if required.\n' >&2
    exit 1
}
docker compose version || exit 1
docker info --format 'OS={{.OSType}} Architecture={{.Architecture}} Runtimes={{json .Runtimes}}' || exit 1

section 'Existing image tags (no pull)'
docker image ls --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}' || exit 1

section 'Current container names and published ports'
docker ps --format '{{.Names}} {{.Image}} {{.Ports}}' || exit 1

section 'NVIDIA host driver and container utilities'
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
else
    printf 'nvidia-smi not found\n'
fi
for tool in nvidia-ctk nvidia-container-cli; do
    if command -v "$tool" >/dev/null 2>&1; then
        "$tool" --version
    else
        printf '%s not found in PATH\n' "$tool"
    fi
done

section 'Listening TCP ports'
ss -ltn || exit 1

section 'Network reachability (401 from a registry is normal)'
if command -v curl >/dev/null 2>&1; then
    for url in https://registry-1.docker.io/v2/ https://mcr.microsoft.com/v2/ https://github.com https://archive.ubuntu.com/ubuntu/; do
        curl -I --connect-timeout 10 --max-time 20 --silent --show-error "$url" || printf 'Request failed: %s\n' "$url"
    done
else
    printf 'curl not found; network checks were not executed\n'
fi

section 'Inventory finished'
printf 'This report does not verify GPU access inside containers or training.\n'
