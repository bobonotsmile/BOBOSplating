# BOBOSplating

[简体中文](README.md) | [English](README.en.md)

**A self-hosted 3D Gaussian Splatting Web UI for Windows and Linux.**

Turn a video into a 3D scene you can explore. Deploy BOBOSplating on your own computer or GPU server, then use your browser to upload videos, start reconstruction, track progress, and view or download the resulting Gaussian PLY.

Reconstruction runs on the host machine; the browser provides controls and 3D previews. Source media, job records, and training results stay on your own host, making it suited to personal and trusted internal workspaces.

## Demo video

[Watch the BOBOSplating platform demo (MP4)](docs/assets/BOBOSplating平台演示-GitHub.mp4)

## Features

- **Video to 3D scene**: upload MP4, MOV, MKV, or WebM files for automatic frame extraction, camera reconstruction, and Gaussian training.
- **Two quality profiles**: choose Quick preview for an initial look or Balanced for more detail.
- **Browser-based job management**: follow processing stages, training progress when reported by the engine, elapsed time, reconstruction metrics, and logs. Cancel jobs when needed.
- **Background processing**: jobs run sequentially and continue after you close the page. Return later to check the results.
- **Built-in 3D viewer**: orbit, pan, and zoom around reconstructed scenes, or open an existing local Gaussian PLY. Local preview files are not uploaded to the backend.
- **Downloadable results**: save the final PLY for further viewing and use.

## Workflow

```text
Upload video → Choose quality → Automatic reconstruction and training → View in browser → Download PLY
```

Default upload limits are 1 GiB and 60 minutes. Videos are sampled to the frame limit of the selected profile.

| Profile | Maximum frames | Training steps | Gaussian limit | Maximum image dimension |
| --- | ---: | ---: | ---: | ---: |
| Quick preview | 80 | 5,000 | 500,000 | 1,280 |
| Balanced | 160 | 15,000 | 1,000,000 | 1,600 |

Use videos of static scenes captured with a single lens and fixed focal length. VRAM requirements vary with the footage. Gaussian scenes support novel-view rendering; they are not triangle meshes and do not reconstruct animations of moving subjects.

## Releases and platforms

Release packages will be distributed through **GitHub Releases**. Choose the package for your platform, follow its included deployment instructions, and access the Web UI through your browser.

The Ubuntu installation attachment includes application images and their runtime dependencies. Extract it and use `install.sh`; application installation requires no image registry downloads or compilation on the server. You can choose the installation directory, and full deployment instructions are included.

| Platform | Release format |
| --- | --- |
| Windows x64 | Planned native services using Caddy and NSSM; no installation package currently available |
| Linux (Ubuntu 24.04 x86_64) | Docker Compose installation package; current priority platform |

## Before installing

| Item | Ubuntu requirements and limitations |
| --- | --- |
| Operating system | Ubuntu 24.04, x86_64 (amd64); not an ARM or native Windows package |
| GPU | An NVIDIA GPU with Vulkan support and a compatible host driver already installed; RTX 3060 12GB is the current test configuration, not a minimum VRAM specification. Other GPUs require validation |
| Prerequisites | Working Docker Engine and Compose v2 installations; tested with Docker 28 / Compose 2.34 |
| Permissions | sudo is required. Initial NVIDIA container runtime setup requires confirmation to restart Docker, affecting other containers on the same host |
| Browser access | Enter a server IP or DNS name reachable from your browser. HTTPS uses port 9134 by default; the self-signed certificate requires trust configuration on client devices |
| Processing time | COLMAP feature extraction and matching currently run on the CPU; Brush training uses the GPU. Matching can take several minutes or longer, with logs updated per processing block. Duration depends on the CPU, image count, and scene content |

The host-machine video-to-PLY workflow and NVIDIA/Vulkan visibility inside containers have been verified on the RTX 3060 host. End-to-end training through the current installation package, installation on a fresh host, and native Windows training still await acceptance. Available platforms and validation scope will be listed in each published Release.

The current version is intended for trusted environments and does not provide accounts or multi-user isolation. Unfinished jobs must be resubmitted after a service restart.

## Technology stack

| Component | Technology |
| --- | --- |
| Web UI | Vue 3, JavaScript, Vite, pnpm |
| Backend and job scheduling | C#, ASP.NET Core 6 Web API |
| Frame extraction | FFmpeg / FFprobe |
| Camera poses and sparse reconstruction | COLMAP |
| Gaussian training | Brush |
| Browser 3D viewer | Three.js, Spark |

For source development, configuration, and testing, see the [local development and testing guide (Chinese)](docs/本地测开说明.md).

## License

Original project code is licensed under the [Apache License 2.0](LICENSE). Third-party components retain their own licenses; see the [third-party component notices](docs/THIRD_PARTY_NOTICES.en.md).
