#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")"
[[ $EUID == 0 ]] || { echo '请运行 / Run: sudo bash install.sh'; exit 1; }
source /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 24.04 && $(uname -m) == x86_64 ]] || {
    echo '需要 Ubuntu 24.04 x86_64 / Requires Ubuntu 24.04 x86_64'; exit 1;
}
for cmd in docker python3 openssl curl ss sha256sum nvidia-smi; do
    command -v "$cmd" >/dev/null || { echo "缺少 / Missing: $cmd. 请先阅读部署说明.md 的主机准备部分。"; exit 1; }
done
docker info >/dev/null
docker compose version
docker compose up --help | grep -q -- '--wait' || { echo '请升级 Docker Compose v2，当前版本不支持 --wait'; exit 1; }
nvidia-smi
sha256sum -c checksums.txt
[[ -f .env ]] || cp .env.example .env
if grep -q '^BOBO_PUBLIC_HOST=CHANGE_ME' .env; then
    read -r -p '服务器 IPv4 或 DNS（浏览器使用的地址，不含端口） / Server address: ' public_address
    python3 - "$public_address" <<'PY'
import ipaddress, pathlib, re, sys
host = sys.argv[1]
try:
    assert ipaddress.ip_address(host).version == 4
except ValueError:
    assert len(host) <= 253 and not all(c in '0123456789.' for c in host)
    assert all(re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?', x) for x in host.split('.'))
path = pathlib.Path('.env')
path.write_text(path.read_text().replace('BOBO_PUBLIC_HOST=CHANGE_ME', 'BOBO_PUBLIC_HOST=' + host))
PY
fi
source publish-config/release-common.sh
# Refuse to alter a running deployment. Updates require an explicit stop first.
[[ -z $(docker compose ps -q) ]] || { echo '本实例已有运行容器；更新请先按部署说明停止本实例。'; exit 1; }
while IFS= read -r port; do
    [[ -z $(ss -H -ltn "sport = :$port") ]] || { echo "端口已占用 / Port occupied: $port"; exit 1; }
done < <(cfg --ports)
bash prepare.sh
bash load-images.sh
if ! docker info --format '{{json .Runtimes}}' | python3 -c 'import json,sys; sys.exit(0 if "nvidia" in json.load(sys.stdin) else 1)'; then
    echo '需要配置 NVIDIA 容器运行时并重启 Docker，可能影响其他容器（如 Dify）。'
    echo 'NVIDIA runtime setup requires restarting Docker and may affect other containers.'
    read -r -p '现在允许重启 Docker？输入 RESTART 确认，其他输入退出: ' answer
    [[ $answer == RESTART ]] || { echo '已保留配置和镜像；安排停机后重新运行 install.sh。'; exit 1; }
    bash install-gpu-runtime.sh --restart-docker
fi
bash start.sh
echo "安装完成 / Installed: https://$(cfg BOBO_PUBLIC_HOST):$(cfg BOBO_HTTPS_PORT)"
echo '浏览器证书信任和首次训练验证见 部署说明.md / See deployment guide for certificate trust and first training.'
