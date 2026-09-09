"""Fetch pinned Linux assets from upstream HTTPS endpoints, verify before saving."""
from pathlib import Path
import hashlib
import json
import urllib.request

root = Path(__file__).resolve().parent / "assets"
root.mkdir(exist_ok=True)
assets = [
    ("brush-app-x86_64-unknown-linux-gnu.tar.xz", "https://github.com/ArthurBrussee/brush/releases/download/v0.3.0/brush-app-x86_64-unknown-linux-gnu.tar.xz", "4f0f9a8785d1951c62df26aae247c02c5bba32b00f40b06df4e1c9b867399e20"),
]
nvidia = {
    "libnvidia-container-tools": "6535704295d041b2d51f0364e4a65b8631325bb93921b7fe08266cd4aed66e59",
    "libnvidia-container1": "326da26f762a24f93c251b4c4932dec187426260284d2ae16351cb7178a1e87f",
    "nvidia-container-toolkit-base": "28a6f2d41913897effe923b46234998f878fc21b32941ea9a2b878efa62b2267",
    "nvidia-container-toolkit": "da7bb4acbd6027349fb5936dfed7e6394592c40a5392ca43172e2356d5b539b5",
}
for package, digest in nvidia.items():
    name = f"{package}_1.20.0-1_amd64.deb"
    assets.append(("nvidia-toolkit/" + name, "https://nvidia.github.io/libnvidia-container/stable/deb/amd64/" + name, digest))
for name, url, digest in assets:
    destination = root / name
    if destination.exists() and hashlib.sha256(destination.read_bytes()).hexdigest() == digest:
        print("Verified existing:", name)
        continue
    payload = urllib.request.urlopen(url, timeout=120).read()
    if hashlib.sha256(payload).hexdigest() != digest:
        raise ValueError("SHA256 mismatch: " + name)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(payload)
    print("Downloaded and verified:", name)
(root / "nvidia-toolkit/SHA256SUMS").write_text("".join(
    digest + "  " + Path(name).name + "\n" for name, _, digest in assets if name.startswith("nvidia-toolkit/")), encoding="utf-8")
(root / "asset-sources.json").write_text(json.dumps([
    {"file": name, "url": url, "sha256": digest} for name, url, digest in assets], indent=2) + "\n", encoding="utf-8")
