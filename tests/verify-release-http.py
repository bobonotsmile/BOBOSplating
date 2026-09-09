"""Local release integration. GPU explicitly omitted here, tools replaced only for orchestration checks."""
from pathlib import Path
import json
import shutil
import socket
import ssl
import subprocess
import time
import urllib.request
import urllib.error

root = Path(__file__).resolve().parent.parent
fixture = root / "tests" / "release integration with spaces"
fixture.mkdir(exist_ok=True)
(fixture / "data").mkdir(exist_ok=True)
(fixture / "publish-config/certs").mkdir(parents=True, exist_ok=True)
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
env = (root / ".env.example").read_text(encoding="utf-8").replace("COMPOSE_PROJECT_NAME=bobosplating", "COMPOSE_PROJECT_NAME=bobo-release-check")
env = env.replace("BOBO_PUBLIC_HOST=CHANGE_ME", "BOBO_PUBLIC_HOST=localhost").replace("BOBO_HTTPS_PORT=9134", f"BOBO_HTTPS_PORT={port}")
(fixture / ".env").write_text(env, encoding="utf-8")
(fixture / "compose.yml").write_text((root / "compose.yml").read_text(encoding="utf-8").replace("dev-config/", "publish-config/"), encoding="utf-8")
config = json.loads(subprocess.check_output(["docker", "compose", "config", "--format", "json"], cwd=fixture, text=True))
backend = config["services"]["splat-backend"]
backend.pop("deploy")  # Local WSL test does not claim NVIDIA Vulkan support.
backend.pop("runtime", None)  # NVIDIA runtime is verified separately on the target host.
backend.pop("build")
config["services"]["web-frontend"].pop("build")
config["services"]["web-frontend"]["ports"][0]["host_ip"] = "127.0.0.1"
config_file = fixture / "compose-test.json"
config_file.write_text(json.dumps(config, indent=2), encoding="utf-8")
image = backend["image"]
subprocess.run(["docker", "run", "--rm", "--pull", "never", "--user", "0:0", "--mount",
    f"type=bind,source={fixture / 'publish-config/certs'},target=/certs", image, "openssl", "req", "-x509", "-nodes",
    "-newkey", "rsa:2048", "-keyout", "/certs/server.key", "-out", "/certs/server.crt", "-subj", "/CN=localhost",
    "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1"], check=True, capture_output=True)
context = ssl.create_default_context(cafile=str(fixture / "publish-config/certs/server.crt"))
client = urllib.request.build_opener(urllib.request.ProxyHandler({}), urllib.request.HTTPSHandler(context=context))
base = f"https://localhost:{port}"
checks = 0
def check(ok, label):
    global checks
    assert ok, label
    checks += 1
    print("PASS:", label, flush=True)
def compose(*args):
    subprocess.run(["docker", "compose", "-f", str(config_file), *args], cwd=fixture, check=True)
def request(path, data=None, headers=None):
    req = urllib.request.Request(base + path, data=data, headers=headers or {})
    try:
        with client.open(req, timeout=20) as response: return response.status, response.read()
    except urllib.error.HTTPError as response: return response.code, response.read()
def get(path):
    status, body = request(path)
    assert status == 200, (path, status, body)
    return json.loads(body)
def submit(contents):
    boundary = "BoboReleaseCheckBoundary"
    data = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"profile\"\r\n\r\nquick\r\n"
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"video\"; filename=\"test.mp4\"\r\n"
            f"Content-Type: video/mp4\r\n\r\n{contents}\r\n--{boundary}--\r\n").encode()
    status, body = request("/api/jobs", data, {"X-Bobo-Client": "web", "Content-Type": "multipart/form-data; boundary=" + boundary})
    assert status == 202, (status, body)
    return json.loads(body)["id"]
def wait(job_id):
    for _ in range(200):
        job = get("/api/jobs/" + job_id)
        if job["status"] in ("completed", "failed", "cancelled", "interrupted"): return job
        time.sleep(.1)
    raise AssertionError("Job timeout")
try:
    compose("up", "-d", "--no-build", "--pull", "never", "--wait", "--wait-timeout", "120")
    check(get("/api/health")["status"] == "ok", "HTTPS certificate + health proxy")
    check(get("/api/settings")["toolsReady"], "real native tool paths present")
    status, html = request("/")
    check(status == 200 and b'<div id="app">' in html, "production frontend HTML")
    import re
    asset = re.search(rb'src="([^"]+\.js)"', html).group(1).decode()
    check(request(asset)[0] == 200, "production JS asset")
    check(request("/nested/route")[0] == 200, "SPA refresh fallback")
    check(request("/api/jobs", b"x")[0] == 403, "custom POST header enforced through proxy")
    invalid = wait(submit("not-a-real-video"))
    check(invalid["status"] == "failed" and invalid["stage"] == "probe", "real FFprobe rejects invalid media in Ubuntu image")
    compose("down", "--remove-orphans")
    fake = fixture / "fake"
    fake.mkdir(exist_ok=True)
    for name in ("FakeEngine.dll", "FakeEngine.deps.json", "FakeEngine.runtimeconfig.json"):
        shutil.copy2(root / "tests/FakeEngine/bin/Release/net6.0" / name, fake / name)
    wrapper = fake / "engine"
    wrapper.write_bytes(b'#!/bin/sh\nexec dotnet /fake/FakeEngine.dll "$@"\n')
    subprocess.run(["docker", "run", "--rm", "--pull", "never", "--user", "0:0", "--mount", f"type=bind,source={fake},target=/fake", image, "chmod", "755", "/fake/engine"], check=True)
    backend["volumes"].append({"type": "bind", "source": str(fake), "target": "/fake", "read_only": True})
    for tool in ("Ffmpeg", "Ffprobe", "Colmap", "Brush"):
        backend["environment"]["Bobo__Tools__" + tool] = "/fake/engine"
    config_file.write_text(json.dumps(config, indent=2), encoding="utf-8")
    compose("up", "-d", "--no-build", "--pull", "never", "--wait", "--wait-timeout", "120")
    job = wait(submit("ok"))
    check(job["status"] == "completed", "Ubuntu image full orchestration using test tools")
    status, body = request(f"/api/jobs/{job['id']}/scene.ply", headers={"Range": "bytes=0-2"})
    check(status == 206 and body == b"ply", "PLY byte ranges through HTTPS proxy")
    check(any("5000/5000" in x for x in get(f"/api/jobs/{job['id']}/logs")), "training log API through proxy")
    slow = submit("slow")
    time.sleep(.5)
    check(request(f"/api/jobs/{slow}/cancel", b"", {"X-Bobo-Client": "web"})[0] == 202, "cancel API through proxy")
    check(wait(slow)["status"] == "cancelled", "running process cancelled")
    compose("down", "--remove-orphans")
    compose("up", "-d", "--no-build", "--pull", "never", "--wait", "--wait-timeout", "120")
    check(get(f"/api/jobs/{job['id']}")["status"] == "completed", "data survives container removal and reinstall")
    check(request(f"/api/jobs/{job['id']}/scene.ply")[0] == 200, "PLY survives reinstall")
    print(f"All {checks} release HTTP checks passed; target GPU and browser acceptance NOT asserted.", flush=True)
finally:
    logs = subprocess.run(["docker", "compose", "-f", str(config_file), "logs", "--no-color"], cwd=fixture, text=True, capture_output=True)
    (fixture / "containers.log").write_text(logs.stdout + logs.stderr, encoding="utf-8")
    compose("down", "--remove-orphans")
