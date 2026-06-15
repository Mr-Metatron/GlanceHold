# GlanceHold

[English README](README.md)

GlanceHold 是一个面向 IINA 长视频观看场景的 macOS 状态栏工具。它使用 Mac 内置摄像头和 Apple Vision 估计你的头部是否正对屏幕，并在注意力离开和回来时用克制的方式控制播放。

GlanceHold 当前支持 IINA。在速度控制（Speed Control）模式下，你看向别处时，GlanceHold 会把 IINA 降到 1x；你重新看向屏幕后，它会恢复介入前捕获到的播放速度。如果你更希望直接暂停和恢复，也可以使用暂停/恢复（Pause/Resume）模式。

摄像头画面留在你的 Mac 上。摄像头画面会本地处理，不会保存，不会上传。GlanceHold 通过本地回环桥接与 GlanceHold Bridge IINA 插件通信；协议和信任模型细节见 [IINAPlugin/README.md](IINAPlugin/README.md)。

GlanceHold 不是眼动追踪。它不知道你正在看屏幕上的哪个位置。

## 目录

- [适合你吗？](#适合你吗)
- [兼容性与限制](#兼容性与限制)
- [从 Latest Release 安装](#从-latest-release-安装)
- [校准建议](#校准建议)
- [开发者与源码路径](#开发者与源码路径)
- [使用方式](#使用方式)
- [故障排查](#故障排查)
- [GitHub Release 正文合同](#github-release-正文合同)

## 适合你吗？

GlanceHold 适合用 IINA 看网课、讲座或长视频，并希望自己看向别处时播放压力自动降低的用户。当前支持路径是 IINA 加上匹配版本的 GlanceHold Bridge 插件。

如果你通常用 1x 以上倍速观看，并希望离开注意力时暂时保持在 1x，请选择速度控制（Speed Control）。如果你希望 GlanceHold 在看走时暂停，并且只恢复由 GlanceHold 自己暂停的视频，请选择暂停/恢复（Pause/Resume）。

## 兼容性与限制

- 需要 macOS 14 或更高版本。
- 需要可用摄像头和 macOS 摄像头权限。
- 需要 IINA 以及匹配版本的 GlanceHold Bridge 插件。
- 当前支持 IINA；当前 release 不支持其他播放器。
- GlanceHold 估计的是实用的“是否正对屏幕”信号；它不会识别你正在看屏幕的哪个具体区域。

## 从 Latest Release 安装

1. 打开 [Latest Release](https://github.com/Mr-Metatron/GlanceHold/releases/latest)。
2. 阅读该 Release 正文，找到匹配的 GlanceHold app DMG 和 GlanceHold Bridge 插件包。具体文件以该 Release 正文为准，包括 `GlanceHold-<app-version>-build-<build>.dmg` 和 `GlanceHoldBridge-<app-version>-build-<build>.iinaplgz`。
3. 启动前，用该 Release 正文中的 SHA-256 校验和验证下载到的 app artifact。
4. 此版本未签名、未公证；安装需要通过 macOS 手动打开 / Open Anyway。校验和验证通过后，如果 macOS 阻止首次启动，可以右键 app 选择 Open，或在 System Settings -> Privacy & Security 中选择 Open Anyway。
5. 安装匹配的 GlanceHold Bridge 插件：使用与 app 来自同一个 GitHub Release 的 `GlanceHoldBridge-<app-version>-build-<build>.iinaplgz`，或使用同一个 DMG 中的插件包，用 IINA 打开/安装它，重启 IINA，在 IINA 中确认 `GlanceHold Bridge` 已启用，然后回到 GlanceHold。详细插件说明见 [IINAPlugin/README.md](IINAPlugin/README.md)。
6. 打开 IINA 并载入一个可播放的视频。
7. 启动 GlanceHold，打开状态栏菜单，选择 `校准正对屏幕姿态`（Calibrate Facing Pose）。
8. macOS 询问时授予摄像头权限。只有在你选择校准或开启监控后，摄像头访问才会开始。
9. 以正常观看姿势正对屏幕，在平常光照下等待校准成功。
10. 选择 `开启监控`（Enable Monitoring）。
11. 使用 `速度控制`（Speed Control）获得默认的离开时保持 1x 行为，或切换到 `暂停/恢复`（Pause/Resume）。
12. 如果之后保存的正对姿态不再符合你的实际位置，使用 `重置校准`（Reset Calibration）。

## 校准建议

监控使用摄像头信号前需要先校准。请坐在平常观看 IINA 的位置，自然正对屏幕，让摄像头能看见你的脸，并使用稳定的室内光照；尽量避免强侧光、背光或脸部被遮挡。

如果出现 `校准失败`，请保持正对屏幕，改善光照或摄像头可见度后重试。如果之前已有有效校准，失败的重试会保留原校准。桌面、摄像头角度、座位距离、正常观看姿势发生明显变化，或你觉得保存姿态不准时，使用 `重置校准`；重置后需要再次运行 `校准正对屏幕姿态`，然后才能开启监控。

## 开发者与源码路径

源码开发时，可以在 Xcode 中打开 `GlanceHold.xcodeproj`，或从 Xcode 构建并运行 `GlanceHold` scheme。App target 使用 AVFoundation 捕获摄像头画面，使用 Vision 生成本地的正对屏幕信号，启用 App Sandbox 摄像头 entitlement，并通过 `com.apple.security.network.client` 与 IINA 本地 WebSocket bridge 通信。

插件协议和本地信任模型细节见 [IINAPlugin/README.md](IINAPlugin/README.md)。源码树中的插件文件和开发链接路径只用于开发和本地测试，不是默认的 release 用户路径。桥接协议测试可以这样运行：

```zsh
node IINAPlugin/GlanceHoldBridge.protocol.test.js
```

## 使用方式

状态栏菜单会显示当前监控状态、可用时的 IINA 状态，以及 GlanceHold 做出有意义播放或安全动作后的 `上次操作`（Last Action）。

### 速度控制

速度控制（Speed Control）是主要模式。你看向别处或离开画面并超过配置的离开延迟后，GlanceHold 会把 IINA 速度设为 1x。你重新正对屏幕并经过恢复延迟后，它会恢复 GlanceHold 介入前捕获到的速度，例如 1.25x、1.5x 或 2x。

### 暂停/恢复

暂停/恢复（Pause/Resume）会在你看向别处时暂停 IINA，并且只在这次暂停由 GlanceHold 造成时恢复播放。如果你手动暂停 IINA，GlanceHold 会把它视为用户接管，不会自动恢复视频。

### 校准

校准会记录你的中性正对屏幕姿态。如果因为没有检测到稳定人脸而校准失败，请在正常光照下正对屏幕重试。当之前已有有效校准时，失败的校准会保留旧校准。

当保存的姿态感觉不对时，使用 `重置校准`。重置后，监控会回到需要校准的状态。

### IINA 插件

IINA 插件让沙盒中的状态栏 app 通过一个范围很窄的本地桥接与 IINA 通信。GlanceHold 使用它读取 IINA 状态、设置速度、暂停、恢复，并接收插件的 `Option-G` 监控切换请求。

GlanceHold 连接到 `ws://127.0.0.1:47873`。这是本机回环桥接，不是通用远程控制 API，也没有远程主机配置。同一台 Mac 上的其他进程可能尝试连接这个本地端口，因此插件只接受 GlanceHold 协议形状和白名单命令：`snapshot`、`setSpeed`、`pause`、`resume`。更完整的信任模型见 [IINAPlugin/README.md](IINAPlugin/README.md)。

桥接连接成功后，GlanceHold 菜单中的 IINA 行应从设置或不可用状态变为 IINA idle、paused、playing 或不可控制等状态，具体取决于 IINA 播放情况。

### 上次操作

`上次操作`（Last Action）只会在 GlanceHold 执行播放或安全工作后出现，例如 `Held speed at 1x`、`Restored speed to 2x`、`Paused by GlanceHold`、`Resumed playback`、`Manual pause detected` 或 `Stopped monitoring`。

摄像头权限、需要校准、没有检测到人脸、看向别处、恢复中、IINA 可用性等准备状态会留在 Status 和 IINA 行，而不是变成 Last Action。

### 关闭监控与退出

`关闭监控`（Disable Monitoring）会停止注意力监控和摄像头捕获，清除 GlanceHold 内部的播放所有权，并记录 `Stopped monitoring`。

`退出 GlanceHold`（Quit）会停止监控、停止本地状态流、清除 GlanceHold 播放所有权，然后退出。

这两个路径都刻意采用 stop-only 清理。即使 GlanceHold 最近降低过速度或暂停过 IINA，关闭监控和退出时也不会发送恢复速度或恢复播放命令。下一次监控会先重新读取 IINA 状态，再做新的播放决策。

## 故障排查

### 需要摄像头权限或摄像头权限已拒绝

如果菜单显示 `需要摄像头权限` 或摄像头权限已拒绝，请选择 GlanceHold 菜单中显示的操作，并在 macOS 设置中允许摄像头访问。如果之前拒绝过权限，请打开 System Settings，允许 GlanceHold 使用摄像头，然后再次开启监控。

### 校准失败

如果出现 `校准失败`，请在正常观看位置正对屏幕，改善光照或摄像头可见度，然后再次选择 `校准正对屏幕姿态`。如果之前已有有效校准，失败的重试会保留旧校准。

### 重置校准

桌面、摄像头角度、座位位置或正常观看姿势变化后，请使用 `重置校准`。重置后，监控会回到需要校准的状态，你必须再次运行 `校准正对屏幕姿态`。

### IINA 桥接等待中或不可用

如果 IINA 行显示 `IINA 桥接等待中`、需要设置或不可用，请确认 IINA 已打开，匹配版本的 GlanceHold Bridge 插件已安装并启用，并且 IINA 已载入可播放视频。安装或更改插件后请重启 IINA。

### 需要更新 IINA Bridge

更新或重新安装 GlanceHold IINA 插件，然后重启 IINA。

### 速度或暂停没有变化

如果可见症状是速度或暂停没有变化，请检查监控是否已开启、校准是否成功、IINA 是否正在播放可控制内容、GlanceHold Bridge 是否已连接，以及当前选择的模式是否符合预期。在速度控制（Speed Control）模式下，可见变化是速度降到 1x 后再恢复。在暂停/恢复（Pause/Resume）模式下，可见变化是暂停和恢复。

### 检测到手动暂停

如果你手动暂停或以其他方式接管播放，GlanceHold 会出于安全停止监控，并显示 `Manual pause detected`。需要 GlanceHold 重新接管时，请再次开启监控，让它重新读取当前状态。

### 关闭监控后 IINA 留在 1x 或暂停

这是预期的 stop-only 行为。关闭监控和退出会把控制权交还给你，不发送恢复速度或恢复播放命令。

## GitHub Release 正文合同

每个 GitHub Release 正文都是该版本的权威发布说明位置。README 会链接到 [Latest Release](https://github.com/Mr-Metatron/GlanceHold/releases/latest)，但具体版本的 release-specific 事实必须写在对应 Release 正文中。

每个 GitHub Release 正文必须包含：

- 应用版本/构建号
- IINA Bridge 插件包文件名：`GlanceHoldBridge-<app-version>-build-<build>.iinaplgz`
- IINA Bridge 插件版本
- 桥接协议版本
- DMG 文件名
- SHA-256 校验和
- 签名/公证状态：此版本未签名、未公证；安装需要通过 macOS 手动打开 / Open Anyway。
- 已验证 macOS
- 已验证 Xcode
- 已验证 IINA
- 已知限制

Release 正文只陈述该版本实际的签名/公证状态；如果未来某个版本已公证，也只应把它作为实际发布状态说明，不把它描述成对应用隐私行为的评估。

Release 正文里的已知限制只列新增、变更或特别重要的 release-specific 限制；基线限制留在 README。
