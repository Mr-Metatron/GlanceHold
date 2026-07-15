# GlanceHold

[English README](README.md)

GlanceHold 是一款 macOS 状态栏实用工具，专为在 IINA 中长时间观看视频而设计。它利用 Mac 内置摄像头和 Apple Vision 判断你的头部是否朝向屏幕，并在你注意力离开或返回时，采取保守的播放控制措施。

GlanceHold 目前支持 IINA 播放器，并提供两种模式：

- **速度控制模式（Speed Control）**：当你移开视线时，视频速度降至正常速度（1x），重新看向屏幕后自动恢复到之前设置的速度。
- **暂停/恢复模式（Pause/Resume）**：当你移开视线时自动暂停，重新看向屏幕后恢复播放。

摄像头图像数据仅在本地处理，不会被存储或上传。GlanceHold 使用本地环回桥（loopback bridge）与 GlanceHold Bridge IINA 插件通信；协议和信任模型细节请参考 [IINAPlugin/README.md](IINAPlugin/README.md)。

GlanceHold 并非眼动追踪工具，无法识别你在屏幕上的具体注视位置。

## 目录

- [适用人群](#适用人群)
- [兼容性及限制](#兼容性及限制)
- [从 Latest Release 安装](#从-latest-release-安装)
- [校准指南](#校准指南)
- [开发者信息与源码说明](#开发者信息与源码说明)
- [使用方法](#使用方法)
- [常见问题排查](#常见问题排查)
- [许可协议](#许可协议)

## 适用人群

GlanceHold 面向长期观看课程、讲座或长视频的 IINA 用户，尤其适合希望在视线离开时自动降低播放压力的场景。目前仅支持搭配对应版本 GlanceHold Bridge 插件的 IINA。

- **速度控制模式（Speed Control）**：适合平时习惯以超过 1x 倍速观看视频，并希望注意力移开时暂时恢复到正常速度的用户。
- **暂停/恢复模式（Pause/Resume）**：适合希望 GlanceHold 只在自动触发暂停后，才自动恢复播放的用户。

## 兼容性及限制

- 需要 macOS 14 或更新版本。
- 需要正常工作的摄像头，并授予 macOS 摄像头权限。
- 需要 IINA 及对应版本的 GlanceHold Bridge 插件。
- 目前不支持其他视频播放器。
- GlanceHold 仅识别头部是否朝向屏幕的实用信号，无法确定你注视屏幕的具体区域。

## 从 Latest Release 安装

1. 打开 [Latest Release](https://github.com/Mr-Metatron/GlanceHold/releases/latest)。
2. 在发布页面中下载对应版本的 GlanceHold 应用 DMG 和 GlanceHold Bridge 插件包。具体文件以该 Release 正文为准，包括 `GlanceHold-<app-version>-build-<build>.dmg` 和 `GlanceHoldBridge-<app-version>-build-<build>.iinaplgz`。
3. 打开应用前，根据该 Release 正文提供的 SHA-256 校验和验证下载到的应用文件。
4. 应用未签名且未经过公证，安装时需要通过 macOS 手动打开 / Open Anyway。校验通过后，如果 macOS 阻止首次启动，可以右键 app 选择 Open，或在 System Settings -> Privacy & Security 中选择 Open Anyway。
5. 安装对应的 GlanceHold Bridge 插件：使用与 app 来自同一个 GitHub Release 的 `GlanceHoldBridge-<app-version>-build-<build>.iinaplgz`，或使用同一个 DMG 中的插件包，用 IINA 打开/安装它，重启 IINA，在 IINA 中确认 `GlanceHold Bridge` 已启用，然后回到 GlanceHold。详细插件说明见 [IINAPlugin/README.md](IINAPlugin/README.md)。
6. 打开 IINA 并载入一个可播放的视频。
7. 启动 GlanceHold，打开状态栏菜单，选择 `校准正对屏幕姿态`（Calibrate Facing Pose）。
8. macOS 请求摄像头权限时允许。只有在你选择校准或开启监控后，摄像头访问才会开始。
9. 在正常观看视频的位置和光照下，正对屏幕等待校准成功。
10. 选择 `开启监控`（Enable Monitoring）。
11. 默认使用 `速度控制`（Speed Control）模式，或根据需要切换到 `暂停/恢复`（Pause/Resume）模式。
12. 如果之后保存的正对屏幕姿态不再符合你的实际环境，使用 `重置校准`（Reset Calibration）。

每次正式发布时，请在 GitHub Release 正文中分别记录：IINA Bridge 插件包文件名、IINA Bridge 插件版本和桥接协议版本。

## 校准指南

启用监控前必须完成校准。请坐在日常观看 IINA 的位置，自然面对屏幕，保持摄像头可清晰捕捉到面部，并使用稳定的室内照明，避免强侧光、背光或脸部被遮挡。

如果出现 `校准失败`，请保持正对屏幕，调整光照或摄像头可见度后重试。若之前已成功校准，新校准失败时将保留原校准数据。桌面、摄像头角度、座位位置或正常观看姿势发生明显变化，或你觉得保存的姿态不准确时，请先使用 `重置校准`；重置后需要再次运行 `校准正对屏幕姿态`，然后才能开启监控。

## 开发者信息与源码说明

进行源码开发时，可以在 Xcode 中打开 `GlanceHold.xcodeproj`，或使用 Xcode 构建并运行 `GlanceHold` scheme。应用 target 使用 AVFoundation 捕获摄像头图像，使用 Vision 提供本地朝向屏幕信号，启用 App Sandbox 摄像头 entitlement，并通过 `com.apple.security.network.client` 与 IINA 的本地 WebSocket bridge 通信。

插件协议和本地信任模型细节请参考 [IINAPlugin/README.md](IINAPlugin/README.md)。源码树中的插件文件和开发链接路径只用于开发和本地测试，不是默认的 release 用户路径。运行插件协议测试工具：

```zsh
node IINAPlugin/GlanceHoldBridge.protocol.test.js
```

## 使用方法

状态栏菜单显示当前监控状态、可用时的 IINA 状态，以及 GlanceHold 实施播放控制或安全操作后的 `上次操作`（Last Action）。

### 速度控制模式

速度控制（Speed Control）是主要模式。你移开视线或离开摄像范围并超过配置的离开延迟后，GlanceHold 会把 IINA 速度降至 1x。你重新看向屏幕并经过恢复延迟后，它会恢复 GlanceHold 介入前捕获到的播放速度，例如 1.25x、1.5x 或 2x。

### 暂停/恢复模式

暂停/恢复（Pause/Resume）会在你移开视线时暂停 IINA，并且仅当这次暂停由 GlanceHold 引发时才会自动恢复播放。如果你手动暂停 IINA，GlanceHold 会视为用户接管，不会自动恢复视频。

### 校准

校准会记录你正常观看时的中性正对屏幕姿态。如果因为没有检测到稳定面部而校准失败，请确保光照正常并正对屏幕重试。当之前已有有效校准时，失败的校准会继续保留旧校准数据。

当记录的姿态明显偏差时，可以使用 `重置校准`。重置后，监控会回到需要校准的状态。

### IINA 插件

IINA 插件让沙盒中的状态栏 app 通过范围很窄的本地环回桥与 IINA 通信。GlanceHold 使用它读取 IINA 状态、设置速度、暂停、恢复，并接收插件的 `Option-G` 监控切换请求。

GlanceHold 连接到 `ws://127.0.0.1:47873`。同一台 Mac 上的其他进程可能尝试连接这个本地端口，因此插件只接受 GlanceHold 协议格式和白名单请求：`snapshot`、`setSpeed`、`pause`、`resume`。插件无需额外请求令牌。

桥接成功连接后，GlanceHold 菜单中的 IINA 行会根据播放状态，从设置或不可用状态变为空闲、暂停、播放或无法控制等状态。

### 上次操作

`上次操作`（Last Action）仅在 GlanceHold 实施播放控制或安全操作后显示，例如 `Held speed at 1x`、`Restored speed to 2x`、`Paused by GlanceHold`、`Resumed playback`、`Manual pause detected` 或 `Stopped monitoring`。

摄像头权限、需要校准、无面部检测、移开视线、恢复中、IINA 可用性等状态会显示在 Status 和 IINA 行，而不会变成 Last Action。

### 关闭监控与退出

`关闭监控`（Disable Monitoring）会停止注意力检测和摄像头捕获，清除 GlanceHold 内部的播放控制所有权，并记录 `Stopped monitoring`。

`退出 GlanceHold`（Quit）会停止所有监控和本地状态流，清除 GlanceHold 播放控制所有权，然后关闭应用。

关闭监控和退出都采用 stop-only 清理。即使 GlanceHold 最近降低过速度或暂停过 IINA，也不会在关闭时恢复之前的播放速度或播放状态。下一次监控开始前，GlanceHold 会重新读取 IINA 状态。

## 常见问题排查

### 需要摄像头权限或摄像头权限已拒绝

如果菜单显示 `需要摄像头权限` 或摄像头权限已拒绝，请选择 GlanceHold 菜单中显示的操作，并在 macOS 设置中允许摄像头访问。如果之前拒绝过权限，请打开 System Settings，允许 GlanceHold 使用摄像头，然后再次开启监控。

### 校准失败

如果出现 `校准失败`，请在正常观看位置正对屏幕，调整光照或摄像头可见度，然后再次选择 `校准正对屏幕姿态`。如果之前已有有效校准，失败的重试会保留旧校准。

### 重置校准

桌面、摄像头角度、座位位置或正常观看姿势变化后，请使用 `重置校准`。重置后，监控会回到需要校准的状态，你必须再次运行 `校准正对屏幕姿态`。

### IINA 桥接等待中或不可用

如果 IINA 行显示 `IINA 桥接等待中`、需要设置或不可用，请确认 IINA 已打开，匹配版本的 GlanceHold Bridge 插件已安装并启用，并且 IINA 已载入可播放视频。安装或更改插件后请重启 IINA。

### 需要更新 IINA Bridge

更新或重新安装 GlanceHold IINA 插件，然后重启 IINA。

### 速度或暂停没有变化

如果速度或暂停没有按预期变化，请检查监控是否已开启、校准是否成功、IINA 是否正在播放可控制内容、GlanceHold Bridge 是否已连接，以及当前选择的模式是否符合预期。在速度控制（Speed Control）模式下，可见变化是速度降到 1x 后再恢复。在暂停/恢复（Pause/Resume）模式下，可见变化是暂停和恢复。

### 检测到手动暂停

如果你手动暂停或以其他方式接管播放，GlanceHold 会出于安全停止监控，并显示 `Manual pause detected`。需要 GlanceHold 重新接管时，请再次开启监控，让它重新读取当前状态。

### 关闭监控后 IINA 留在 1x 或暂停

这是预期的 stop-only 行为。关闭监控和退出会把控制权交还给你，不发送恢复速度或恢复播放命令。

## 许可协议

GlanceHold 使用 MIT 协议发布。更多信息请参考 [LICENSE](LICENSE)。
