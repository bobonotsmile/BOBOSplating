"""Read Compose's resolved environment without executing .env as shell code."""
import ipaddress
import json
import re
import subprocess
import sys

def environment():
    result = subprocess.run(["docker", "compose", "config", "--environment"],
                            check=True, text=True, capture_output=True)
    return dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)

def validate(env):
    for key in ("BOBO_API_PORT", "BOBO_HTTPS_PORT"):
        value = env.get(key, "")
        if not value.isdecimal() or not 1024 <= int(value) <= 65535:
            raise ValueError(f"{key} must be a port between 1024 and 65535")
    for key in ("BOBO_UID", "BOBO_GID"):
        if not env.get(key, "").isdecimal() or not 1 <= int(env[key]) <= 2147483647:
            raise ValueError(f"{key} must be a non-root numeric ID")
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]*", env.get("COMPOSE_PROJECT_NAME", "")):
        raise ValueError("Invalid COMPOSE_PROJECT_NAME")
    host = env.get("BOBO_PUBLIC_HOST", "")
    if host in ("", "CHANGE_ME") or len(host) > 253:
        raise ValueError("Set BOBO_PUBLIC_HOST to your server IPv4 address or DNS name")
    try:
        address = ipaddress.ip_address(host)
        if address.version != 4:
            raise ValueError("Use IPv4 or a DNS name for this release")
        san = "IP:" + host
    except ValueError:
        if all(c in "0123456789." for c in host) or not all(
            re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", label)
            for label in host.split(".")
        ):
            raise ValueError("BOBO_PUBLIC_HOST must be an IPv4 address or DNS name, without scheme/port")
        san = "DNS:" + host
    if ipaddress.ip_address(env["BOBO_BIND_IP"]).version != 4:
        raise ValueError("BOBO_BIND_IP must be an IPv4 address")
    max_upload = int(env["BOBO_MAX_UPLOAD_BYTES"])
    if max_upload < 1024 or int(env["BOBO_REQUEST_MAX_BYTES"]) != max_upload + 1048576:
        raise ValueError("BOBO_REQUEST_MAX_BYTES must equal BOBO_MAX_UPLOAD_BYTES + 1048576")
    return san

if __name__ == "__main__":
    try:
        env = environment()
        san = validate(env)
        key = sys.argv[1]
        if key == "--validate":
            print("Release configuration: OK")
        elif key == "--san":
            print(san + ",DNS:localhost,IP:127.0.0.1")
        elif key == "--ports":
            config = json.loads(subprocess.check_output(
                ["docker", "compose", "config", "--format", "json"], text=True))
            print("\n".join(str(p["published"]) for s in config["services"].values() for p in s.get("ports", [])))
        else:
            print(env[key])
    except (ValueError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f"Configuration error: {error}")
