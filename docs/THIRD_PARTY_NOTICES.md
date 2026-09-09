# 第三方组件说明

[简体中文](THIRD_PARTY_NOTICES.md) | [English](THIRD_PARTY_NOTICES.en.md)

返回[项目介绍](../README.md)。

BOBOSplating 原创代码使用 [Apache-2.0](../LICENSE) 许可证。该许可证不会改变第三方组件或生成场景内容的许可。

| 组件 | 用途 | 上游许可证 / 来源 |
| --- | --- | --- |
| Vue | 前端框架 | MIT — https://github.com/vuejs/core |
| Three.js | 三维场景与相机控制 | MIT — https://github.com/mrdoob/three.js |
| Spark 2.1.0 | Gaussian 渲染器 | MIT — https://github.com/sparkjsdev/spark |
| Vite | 构建工具 | MIT — https://github.com/vitejs/vite |
| ASP.NET Core | 后端框架 | MIT — https://github.com/dotnet/aspnetcore |
| Brush 0.3.0 | 外部训练程序 | Apache-2.0 — https://github.com/ArthurBrussee/brush |
| COLMAP 3.9.1 | 外部重建程序 | BSD — https://github.com/colmap/colmap |
| FFmpeg / FFprobe | 外部媒体处理程序 | 依具体构建采用 LGPL/GPL — https://ffmpeg.org/legal.html |

本源码仓库不分发原生计算引擎。发布包若携带原生二进制程序，必须保留该具体构建对应的许可证声明，以及适用的源码分发信息。项目的 Apache-2.0 许可证不替代所携带引擎及其依赖的许可证。

前端第三方许可证正文随生产构建输出到 `third-party-licenses.txt`。
