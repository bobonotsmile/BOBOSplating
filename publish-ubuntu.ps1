[CmdletBinding()]
param([switch]$ReuseImages)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
function Run-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}
function Compress-GzipFile([string]$SourcePath, [string]$DestinationPath) {
    if (Test-Path -LiteralPath $DestinationPath) {
        Remove-Item -LiteralPath $DestinationPath -Force
    }
    $source = [IO.File]::OpenRead($SourcePath)
    try {
        $destination = [IO.File]::Create($DestinationPath)
        try {
            $gzip = [IO.Compression.GZipStream]::new($destination, [IO.Compression.CompressionLevel]::Optimal, $true)
            try { $source.CopyTo($gzip) } finally { $gzip.Dispose() }
        } finally { $destination.Dispose() }
    } finally { $source.Dispose() }
}
if (-not (Test-Path -LiteralPath '.env')) { Copy-Item -LiteralPath '.env.example' -Destination '.env' }
Run-Checked 'python' @('dev-config/fetch-assets.py')
Run-Checked 'dotnet' @('build', 'splat-backend/BoboSplat.Api.csproj', '-c', 'Release')
Run-Checked 'dotnet' @('build', 'tests/FakeEngine/FakeEngine.csproj', '-c', 'Release')
Run-Checked 'dotnet' @('run', '--project', 'tests/BoboSplat.Tests.csproj', '-c', 'Release', '--', '.')
Run-Checked 'pnpm.cmd' @('--dir', 'web-frontend', 'test')
Run-Checked 'pnpm.cmd' @('--dir', 'web-frontend', 'build')
Run-Checked 'docker' @('compose', 'config', '-q')
Run-Checked 'docker' @('compose', 'build', 'splat-backend', 'web-frontend')

$finalRoot = Join-Path $PSScriptRoot 'publish/publish-linux-ubuntu'
$stageParent = Join-Path $PSScriptRoot ('publish/.staging-' + [guid]::NewGuid().ToString('N'))
$releaseRoot = Join-Path $stageParent 'bobosplating'
foreach ($folder in @('publish-config/nvidia-toolkit', 'images')) {
    New-Item -ItemType Directory -Path (Join-Path $releaseRoot $folder) -Force | Out-Null
}
$utf8 = [Text.UTF8Encoding]::new($false)
function Write-ReleaseText([string]$RelativePath, [string]$Content) {
    [IO.File]::WriteAllText((Join-Path $releaseRoot $RelativePath), ($Content -replace "`r`n", "`n"), $utf8)
}
foreach ($file in @('LICENSE', 'NOTICE')) { Copy-Item -LiteralPath $file -Destination (Join-Path $releaseRoot $file) -Force }
$composeText = (Get-Content -Encoding UTF8 -LiteralPath 'compose.yml' -Raw).Replace('dev-config/', 'publish-config/')
$composeText = [regex]::Replace($composeText, '(?m)^    build:\r?\n(?:^      .*\r?\n|^        .*\r?\n)*', '')
if ($composeText -match '(?m)^    build:') { throw 'Release must not contain build context' }
Write-ReleaseText 'compose.yml' $composeText
$envLines = Get-Content -Encoding UTF8 -LiteralPath '.env.example' | Where-Object { $_ -match '^(BOBO_(?!BACKEND_URL=|DEV_PORT=)[A-Z_]+|COMPOSE_PROJECT_NAME)=' }
Write-ReleaseText '.env.example' (($envLines -join "`n") + "`n")
if (-not (Test-Path -LiteralPath (Join-Path $releaseRoot '.env'))) { Copy-Item -LiteralPath (Join-Path $releaseRoot '.env.example') -Destination (Join-Path $releaseRoot '.env') }
foreach ($name in @('release-common.sh', 'release-config.py')) {
    Write-ReleaseText "publish-config/$name" ((Get-Content -Encoding UTF8 -LiteralPath "dev-config/$name" -Raw).Replace('dev-config/', 'publish-config/'))
}
foreach ($name in @('install.sh', 'check-host.sh', 'prepare.sh', 'load-images.sh', 'install-gpu-runtime.sh', 'check-gpu.sh', 'start.sh', 'check-services.sh')) {
    Write-ReleaseText $name (Get-Content -Encoding UTF8 -LiteralPath "dev-config/$name" -Raw)
}
Copy-Item -Path 'dev-config/assets/nvidia-toolkit/*' -Destination (Join-Path $releaseRoot 'publish-config/nvidia-toolkit') -Force
$images = (& docker compose config --images)
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve image names' }
$imageTar = Join-Path $releaseRoot 'images/bobosplating-linux-amd64.tar'
$imageArchive = "$imageTar.gz"
if ($ReuseImages) {
    $previousManifest = Get-Content -Raw (Join-Path $finalRoot 'images/image-manifest.json') | ConvertFrom-Json
    foreach ($image in $images) {
        $currentId = & docker image inspect $image --format '{{.Id}}'
        if ($LASTEXITCODE -ne 0 -or -not ($previousManifest | Where-Object { $_.Id -eq $currentId -and $image -in $_.RepoTags })) { throw 'Cached images differ from current build; run without -ReuseImages' }
    }
    $cached = Join-Path $finalRoot 'images/bobosplating-linux-amd64.tar.gz'
    $expected = ((Get-Content (Join-Path $finalRoot 'images/SHA256SUMS')) -split ' ')[0]
    if ((Get-FileHash $cached -Algorithm SHA256).Hash -ne $expected) { throw 'Cached archive checksum mismatch' }
    Copy-Item -LiteralPath $cached -Destination $imageArchive
} else {
    Run-Checked 'docker' (@('save', '-o', $imageTar) + $images)
    Compress-GzipFile $imageTar $imageArchive
    Remove-Item -LiteralPath $imageTar -Force
}
$hash = (Get-FileHash -LiteralPath $imageArchive -Algorithm SHA256).Hash.ToLowerInvariant()
Write-ReleaseText 'images/SHA256SUMS' "$hash  bobosplating-linux-amd64.tar.gz`n"
Write-ReleaseText '部署说明.md' @'
# BOBOSplating Ubuntu 部署说明

适用系统：Ubuntu 24.04 x86_64（amd64），通过 Docker Compose 部署。当前测试配置为 NVIDIA RTX 3060 12GB、Docker 28 / Compose 2.34；这不是最低显存要求，也不代表其他硬件已经验证。ARM 与 Windows 原生系统不适用此包。已验证与未验证项目见根目录 `验证记录.json`。

## 安装要求与使用限制

- 宿主机应具备可运行的 Docker Engine、Compose v2，以及支持 Vulkan 的 NVIDIA GPU 和兼容显卡驱动；需要 sudo 权限。基础命令准备见下方快速安装。
- 应用和训练工具随镜像提供；Docker、Compose、显卡驱动及缺少的 Ubuntu 基础依赖需提前准备，不能把本包视为裸系统的全套离线安装介质。
- 首次配置 NVIDIA 容器运行时可能需要重启 Docker，影响同机其他容器；安装入口会要求显式确认。已有可用运行时直接复用。
- 需要填写浏览器可访问的服务器 IP 或 DNS，默认 HTTPS 端口 9134。自签证书需要在访问设备上配置浏览器信任。
- 当前 COLMAP 特征提取与匹配使用 CPU，Brush 训练使用 GPU。匹配可能持续数分钟或更久，耗时随 CPU、画面数量和场景变化；日志按处理块更新，短时间无新日志不等于卡死。可结合任务日志与进程活动判断。
- 面向个人与可信内网，无账户和多用户隔离。后端或主机重启会中断未完成任务，需重新提交，不支持断点续训。

## 快速安装（推荐）

从 GitHub Release 下载 `BOBOSplating-<版本>-ubuntu24-amd64.tar.gz` 安装附件，不要下载自动生成的 Source code。应用镜像和 NVIDIA 容器运行时安装包已随包提供，安装不拉取镜像、不编译源码。完整性检查由安装入口自动完成，无需手动操作校验文件。

在 Ubuntu 终端中解压下载的附件（将版本占位符换成实际文件名）：

```bash
tar -xzf BOBOSplating-<版本>-ubuntu24-amd64.tar.gz
cd bobosplating
sudo bash install.sh
```

可在安装前把解压目录整体放到 /opt 或其他位置，名字和绝对路径不影响运行。安装入口检查主机、校验文件，首次询问浏览器访问的服务器 IPv4/DNS，生成证书、导入本地镜像并启动。默认端口 9134；需自定义端口、GPU 或运行用户时，先修改 .env。已运行的实例不会被入口自动停止，更新按第 6 节执行。

主机准备：预先安装 Docker Engine、Compose v2 和兼容 GPU 的 NVIDIA 驱动，确保 `sudo docker info`、`sudo docker compose version`、`nvidia-smi` 成功。参考 https://docs.docker.com/engine/install/ubuntu/ 安装 Docker，驱动使用 Ubuntu 的“附加驱动”或设备供应商说明；本包不静默安装或升级这些主机组件。需要 python3、openssl、curl、iproute2、coreutils；Ubuntu 缺少时可联网执行 `sudo apt-get install python3 openssl curl iproute2 coreutils`，离线主机应提前备齐。

未注册 NVIDIA 容器运行时时，入口询问是否允许重启 Docker；输入 RESTART 才使用随包 deb 安装并重启，其他输入安全退出，可安排停机后重试。已有运行时直接复用。不要在有重要容器运行时忽略此提示。完成后按第 5 节配置浏览器证书信任和验证首次训练。

其他 Ubuntu 24.04 x86_64 用户使用同一入口；RTX 3060 12GB 是当前目标测试配置，其他 GPU 的 Vulkan 支持、显存和训练能力需要实测。

## 1. 目录和运行方式

整个目录可放在 `/opt/bobosplating`，也可使用其他目录和名称，包括带空格的目录。操作时进入实际目录，或通过完整路径调用包内脚本。脚本自动定位自身目录。

```text
发布包/
├─ .env                         # 此部署实例的实际配置，修改后保留
├─ .env.example                 # 配置参考
├─ compose.yml                  # 独立 Compose 入口
├─ images/                      # 两个已构建的 Linux amd64 应用镜像压缩归档及校验值
├─ publish-config/              # 配置读取程序、GPU 安装包和证书
│  ├─ nvidia-toolkit/            # 首次 GPU 接入所需的固定版本 deb
│  └─ certs/                    # prepare.sh 首次生成，私钥只保留在服务器
├─ data/                        # prepare.sh 创建：此实例的视频、任务、中间产物和结果
├─ install.sh                   # 统一安装入口
├─ prepare.sh                   # 创建数据目录、生成或验证证书
├─ load-images.sh               # 校验并导入离线镜像
├─ install-gpu-runtime.sh        # 首次配置 NVIDIA 容器运行时，显式重启 Docker
├─ check-gpu.sh                  # NVIDIA/Vulkan/Brush 检查
├─ start.sh                     # 查端口、查 GPU、启动并检查
├─ check-services.sh             # 容器、HTTPS、网页及 API 检查
└─ 部署说明.md
```

此部署实例的数据和证书保存在安装目录中，不依赖其他安装目录或外部工具目录。镜像内部的 `/app`、`/data`、`/opt/brush` 是容器路径，与宿主机安装目录无关。

`COMPOSE_PROJECT_NAME` 固定实例身份，不从文件夹名推导。更改目录时保留这个值；若运行第二套独立实例，必须更换项目名和 HTTPS 端口，并使用另一个完整目录。

## 2. 首次部署前填写配置

复制完整发布包后，在 Ubuntu bash 中进入实际目录。例如：

```bash
cd /opt/bobosplating
```

编辑根目录 `.env`，至少把 `BOBO_PUBLIC_HOST=CHANGE_ME` 改成 Windows 浏览器实际使用的服务器 IPv4 地址或 DNS 名称，不含 `https://`、端口和路径。不要照抄不属于此主机的 IP。

| 配置 | 默认值 | 含义 |
| --- | --- | --- |
| COMPOSE_PROJECT_NAME | bobosplating | 稳定的实例名称，搬迁时保留 |
| BOBO_PUBLIC_HOST | CHANGE_ME | 浏览器实际访问的 IPv4 / DNS，必须修改 |
| BOBO_HTTPS_PORT | 9134 | 宿主机对外 HTTPS 端口 |
| BOBO_BIND_IP | 0.0.0.0 | 宿主机监听地址；需要限制接口时填写本机对应 IPv4 |
| BOBO_API_PORT | 9131 | 容器网络内后端端口，不映射到宿主机 |
| BOBO_UID / BOBO_GID | 1000 / 1000 | 数据目录及后端进程的数字用户/组 ID |
| BOBO_GPU_ID | 0 | 使用的 NVIDIA GPU 编号 |
| BOBO_MAX_UPLOAD_BYTES | 1073741824 | 最大视频文件大小，默认 1 GiB |
| BOBO_REQUEST_MAX_BYTES | 1074790400 | 视频上限加 1048576 字节表单余量，需同步调整 |
| BOBO_MAX_PENDING_JOBS | 20 | 队列配置 |
| BOBO_PROCESS_TIMEOUT_MINUTES | 120 | 单个工具进程超时，非整项任务总时长 |
| BOBO_MIN_REGISTRATION_RATIO | 0.8 | COLMAP 图片注册比例门槛 |

后端通过 Compose 的 environment 接收配置，不靠自动加载 `.env`。发布包只保留部署使用的配置字段。

镜像固定为 `.env` 中的两个应用标签，默认后端 `bobosplating-backend:0.1.0-ubuntu24`、网页 `bobosplating-web:0.1.0`。首次运行无需在 Ubuntu 安装 Node、.NET SDK、FFmpeg、COLMAP 或 Brush：运行依赖已在应用镜像内。

## 3. 准备数据、证书和离线镜像

每条命令成功后再执行下一条。所有操作均从发布包根目录进行；sudo 密码在终端中输入，不写入 `.env`。

```bash
sudo bash prepare.sh
sudo bash load-images.sh
```

prepare.sh 创建 `data/` 并设定顶层目录所有者，同时为实际访问地址生成自签证书；已存在的证书不会覆盖，而是核对有效期、访问地址和私钥匹配。更新时保留原 BOBO_UID/BOBO_GID，避免历史文件权限不一致。

load-images.sh 先核对 gzip 压缩镜像归档的 SHA256，再由 Docker 直接解压导入，并检查 Linux amd64 架构。默认启动使用导入的镜像，不访问 Docker Hub，不执行现场编译。

证书首次生成在目标机完成，因此每个实例具有独立私钥。不要把 `server.key` 复制给浏览器用户。

## 4. 首次准备 GPU 容器运行时

仅当 Docker 尚未注册可用的 NVIDIA 运行时时才需要本节操作，安装入口会自动检查。已有可用运行时无需重复安装。宿主机 nvidia-smi 正常不代表容器可访问 GPU。

包内提供 NVIDIA Container Toolkit 1.20.0-1 的四个官方 amd64 deb，脚本使用校验值核对，不安装或升级显卡驱动，不需要 CUDA Toolkit。先模拟检查已有 Ubuntu 系统依赖；缺依赖会停止，不能直接跳过报错。

此步骤会重启 Docker，可能影响主机上其他项目的容器。安排好停机窗口后执行：

```bash
sudo bash install-gpu-runtime.sh --restart-docker
```

脚本保留已有 Docker 配置的时间戳备份，通过 nvidia-ctk 添加运行时，然后重启 Docker 并核对注册结果。不会修改其他项目的应用配置或数据目录。主机已有更高版本 Toolkit 时脚本拒绝降级，应保留已有版本处理运行时配置。

GPU 运行时属于主机级依赖，正常应用更新不重复安装。安装后检查原有容器恢复情况：

```bash
sudo docker ps
```

本项目使用 Brush 的图形计算路径，所以除了 NVIDIA 工具，还检查 Vulkan 能否枚举 NVIDIA GPU；不是只跑一次 nvidia-smi 就算训练环境通过。

后端 Compose 显式设置 `runtime: nvidia`，让 NVIDIA 运行时注入 Vulkan 驱动配置。仅请求 GPU 设备而使用默认 runc 时，可能出现 nvidia-smi 正常但 Vulkan 找不到驱动的情况；不需要更改其他项目或 Docker 全局默认运行时。

## 5. 启动与验证

```bash
sudo bash start.sh
```

脚本读取 Compose 配置中的对外端口，发现占用即停止；然后检查容器 GPU、Vulkan、Brush CLI，执行：

```bash
sudo docker compose up -d --no-build --pull never --wait --wait-timeout 120
```

最后自动执行 `check-services.sh`。检查内容包括容器健康、数据目录可写、后端实际监听配置、HTTPS 证书和主机名、首页和 API 代理。这里不会跳过 TLS 校验；使用本实例证书和正确的访问主机名检查。

从 Windows 浏览器访问 `https://实际地址:9134`（端口以 .env 为准）。自签证书不会自动得到 Windows 信任：将服务器 `publish-config/certs/server.crt` 公钥证书复制到需要访问的 Windows 客户端，核对来源后导入“受信任的根证书颁发机构”。只有实际浏览器无证书警告才算该客户端信任完成。可临时接受浏览器提示进行测试，但这不代表信任已配置。

若浏览器连接超时，检查主机防火墙、路由及当前配置端口；本包不自动放开防火墙。

上传一段已知可重建的视频，选择快速档，验证阶段、日志、取消、生成 PLY、下载及三维显示。网页关闭后计算继续；后端或主机重启会中断未完成任务，需重新提交，不支持断点续训。

查看状态与日志：

```bash
sudo docker compose ps
sudo docker compose logs --tail=200
sudo bash check-services.sh
```

任务细节日志保存在 `data/<任务ID>/run.log`；任务状态在 job.json。需要清理数据时先停止应用并确认具体任务目录，不删除整个 data 来修复失败任务。

## 6. 更新、停止、卸载与目录搬迁

临时停止和恢复已有容器：

```bash
sudo docker compose stop
sudo docker compose start
```

更新前等待当前训练结束，备份 `.env`、`data/` 和 `publish-config/certs/`。然后在旧目录停止并删除本项目容器和网络：

```bash
sudo docker compose down --remove-orphans
```

将新包内容覆盖到原目录，保留上述配置、数据和证书；对照新 `.env.example` 增补字段，按新包标签更新 BOBO_BACKEND_IMAGE / BOBO_FRONTEND_IMAGE，不用模板覆盖真实配置。依次执行：

```bash
sudo bash prepare.sh
sudo bash load-images.sh
sudo bash start.sh
```

此部署使用预构建离线镜像，更新不执行 `up --build`。源码和 Dockerfile 位于 Git 仓库，不进入安装包。

彻底卸载应用同样使用 `docker compose down --remove-orphans`，保留数据、证书和主机 GPU 运行时。不要使用全局 Docker 清理命令，也不要删除其他项目镜像。

移动或重命名目录：先在旧目录执行 down，再整体移动目录（含隐藏的 .env、data 和证书），进入新目录执行 start.sh。不能在容器仍运行时移动绑定目录。若访问 IP 或 DNS 同时改变，应修改 BOBO_PUBLIC_HOST，并在备份后更换旧证书再运行 prepare.sh。

应用配置 restart: unless-stopped：未被人工停止的容器应在 Docker/主机重启后恢复。主机重启后的实际恢复、GPU 状态、网页访问仍需在目标机验证；重启不会恢复中断的训练。

## 7. 排错顺序与验收边界

- 找不到镜像：先检查 load-images.sh 的校验/导入结果与 .env 镜像标签；不直接换 latest 或拉未知镜像。
- GPU device driver 错误：检查 NVIDIA 容器运行时；不据此重装显卡驱动。
- nvidia-smi 可用但 Vulkan 失败：检查 graphics 驱动能力与容器 Vulkan 枚举结果；不要把它归因于缺 nvcc。
- 端口冲突：停止操作，确认占用者或调整本项目 HTTPS 端口；不结束其他服务。
- HTTPS 名称或信任错误：区分服务器证书地址不匹配与客户端未信任，不修改系统 TLS 设置。
- 重建失败：从任务当前阶段及 run.log 判断。注册率是成功求位姿图片的比例，不是最终画面质量百分比。

每次部署分别记录：安装、覆盖更新、卸载后重装、容器重启、主机重启、HTTPS 客户端信任、上传/查询/日志/取消/下载接口、页面刷新、真实快速档训练与 PLY 浏览。无数据库，无需数据库验证。本地模拟测试和镜像构建通过不能替代目标 GPU 验收。

NVIDIA 工具官方安装说明：https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
'@
foreach ($notice in @('THIRD_PARTY_NOTICES.md', 'THIRD_PARTY_NOTICES.en.md')) {
    $noticeText = Get-Content -Encoding UTF8 -LiteralPath "docs/$notice" -Raw
    $noticeText = $noticeText.Replace('(../LICENSE)', '(LICENSE)')
    $noticeText = [regex]::Replace($noticeText, '(?m)^.*\]\(\.\./README[^)]*\).*\r?\n?', '')
    Write-ReleaseText $notice $noticeText
}
$imageDetails = & docker image inspect @images
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect exported images' }
$manifest = (($imageDetails -join "`n") | ConvertFrom-Json) | Select-Object Id, RepoTags, Os, Architecture, Size
Write-ReleaseText 'images/image-manifest.json' ($manifest | ConvertTo-Json -Depth 5)
Write-ReleaseText '发布状态.json' '{"status":"prepared-for-target-testing","targetGpuVerified":false,"note":"See 验证记录.json and 部署说明.md. Target validation remains required."}'
Run-Checked 'python' @('tests/verify-release-http.py')
Run-Checked 'docker' @('run', '--rm', '--pull', 'never', '--user', '0:0', '--entrypoint', 'bash', '--mount', "type=bind,source=$PSScriptRoot,target=/source,readonly", 'bobosplating-backend:0.1.0-ubuntu24', '/source/tests/verify-install.sh')
Run-Checked 'docker' @('run', '--rm', '--network', 'none', '--pull', 'never', '--mount', "type=bind,source=$PSScriptRoot/dev-config/assets/nvidia-toolkit,target=/offline packages,readonly", 'ubuntu:24.04', 'bash', '-c', 'apt-get --no-download --simulate install /offline\ packages/*.deb && dpkg -i /offline\ packages/*.deb && nvidia-ctk --version')
Write-ReleaseText '验证记录.json' '{"builds":"passed","backendChecks":29,"frontendTests":3,"releaseHttpChecks":14,"installerControlFlowChecks":6,"installerHostOperations":"mocked","offlineDebRealInstall":"passed in network-disabled Ubuntu 24.04 container","targetToolkitInstallation":"passed via user workaround","targetNvidiaSmi":"passed","targetVulkan":"passed in explicit NVIDIA runtime container; RTX 3060, driver 570.211.01","targetGpuTraining":"not verified","targetRebootAndBrowserAcceptance":"not verified"}'
$checksumLines = foreach ($item in Get-ChildItem -LiteralPath $releaseRoot -Recurse -File -Force | Sort-Object FullName) {
    $relative = $item.FullName.Substring($releaseRoot.Length + 1).Replace('\', '/')
    if ($relative -eq '.env' -or $relative -eq 'checksums.txt' -or $relative -match '(^|/)(bin|obj|data|certs|__pycache__)/') { continue }
    $fileHash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$fileHash  $relative"
}
Write-ReleaseText 'checksums.txt' (($checksumLines -join "`n") + "`n")
$version = (Get-Content -Raw 'web-frontend/package.json' | ConvertFrom-Json).version
$archiveName = "BOBOSplating-$version-ubuntu24-amd64.tar.gz"
$archiveTemporary = Join-Path $stageParent $archiveName
Run-Checked 'tar' @('-czf', $archiveTemporary, '-C', $stageParent, 'bobosplating')
Run-Checked 'python' @('tests/verify-release-package.py', $archiveTemporary)
if ((Get-Item $archiveTemporary).Length -ge 2GB) { throw 'GitHub Release asset must be smaller than 2 GiB' }
$archiveFinal = Join-Path $PSScriptRoot "publish/$archiveName"
Move-Item -LiteralPath $archiveTemporary -Destination $archiveFinal -Force
[IO.File]::WriteAllText("$archiveFinal.sha256", ((Get-FileHash $archiveFinal -Algorithm SHA256).Hash.ToLowerInvariant() + "  $archiveName`n"), $utf8)
# The verified archive is the release artifact. Refresh the local expanded copy
# without deleting old IDE-owned build contexts or modifying instance state.
if (Test-Path -LiteralPath $finalRoot) {
    if ((Test-Path (Join-Path $finalRoot 'data')) -or (Test-Path (Join-Path $finalRoot 'publish-config/certs'))) { throw 'Existing package contains instance state; archive is ready but directory replacement refused' }
    if ((Get-FileHash (Join-Path $finalRoot '.env')).Hash -ne (Get-FileHash (Join-Path $finalRoot '.env.example')).Hash) { throw 'Existing .env was customized; archive ready, directory preserved' }
}
New-Item -ItemType Directory -Path $finalRoot -Force | Out-Null
foreach ($item in Get-ChildItem -LiteralPath $releaseRoot -Recurse -File -Force) {
    $target = Join-Path $finalRoot $item.FullName.Substring($releaseRoot.Length + 1)
    New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
    Copy-Item -LiteralPath $item.FullName -Destination $target -Force
}
$resolvedStage = (Resolve-Path -LiteralPath $stageParent).Path
if ((Split-Path $resolvedStage) -ne (Join-Path $PSScriptRoot 'publish') -or (Split-Path $resolvedStage -Leaf) -notmatch '^\.staging-[a-f0-9]{32}$') { throw 'Unexpected staging directory' }
Remove-Item -LiteralPath $resolvedStage -Recurse -Force
Write-Host "Prepared installation archive: $archiveFinal"
Write-Host 'Target GPU, installation and release documentation verification remain required before declaring delivery.'
