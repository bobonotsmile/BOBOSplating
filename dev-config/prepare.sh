#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")"
source publish-config/release-common.sh
[[ $(uname -m) == x86_64 ]] || { echo 'This package requires x86_64' >&2; exit 1; }
[[ $EUID == 0 ]] || { echo 'Run with sudo: data ownership must match the container user.' >&2; exit 1; }
for path in data publish-config/certs; do
    [[ ! -L "$path" ]] || { echo "Symlink is not allowed for $path" >&2; exit 1; }
done
mkdir -p data publish-config/certs
chown "$(cfg BOBO_UID):$(cfg BOBO_GID)" data
chmod 750 data
host=$(cfg BOBO_PUBLIC_HOST)
cert=publish-config/certs/server.crt
key=publish-config/certs/server.key
if [[ -e "$cert" || -e "$key" ]]; then
    [[ -s "$cert" && -s "$key" ]] || { echo 'Incomplete certificate pair; repair before proceeding.' >&2; exit 1; }
    echo 'Existing certificates retained.'
else
    umask 077
    openssl req -x509 -nodes -newkey rsa:2048 -sha256 -days 365 \
        -keyout "$key" -out "$cert" -subj "/CN=$host" -addext "subjectAltName=$(cfg --san)"
    chmod 644 "$cert"
fi
openssl x509 -in "$cert" -noout -checkend 86400
python3 - "$host" "$cert" <<'PY'
import ipaddress, subprocess, sys
host, cert = sys.argv[1:]
try:
    ipaddress.ip_address(host)
    flag = '-verify_ip'
except ValueError:
    flag = '-verify_hostname'
subprocess.run(['openssl', 'verify', '-CAfile', cert, flag, host, cert], check=True)
PY
cert_pub=$(openssl x509 -in "$cert" -pubkey -noout | openssl pkey -pubin -outform DER | sha256sum)
key_pub=$(openssl pkey -in "$key" -pubout -outform DER | sha256sum)
[[ "$cert_pub" == "$key_pub" ]] || { echo 'Certificate and private key do not match' >&2; exit 1; }
echo 'Directories and certificate ready. No containers have been started.'
