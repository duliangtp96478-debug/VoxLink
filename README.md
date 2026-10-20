# VoxLink

VoxLink 是一个将 Android 手机麦克风声音通过局域网传送到 Windows 电脑的音频项目。Windows 端基于 Flutter UI、C++/WASAPI 原生音频核心；Android 端基于 Flutter UI 和 Kotlin AudioRecord 前台服务。

## 源码版本

- **Windows**：`VoxLink_1.0.1_Stable_Source.zip`；集成 Windows Flutter 3.47.6 特定引擎 Fix7 修补工作流（**专用引擎 DLL 未随公开源码仓库分发**）。
- **Android**：`VoxLink_Android_AEC_Test1_Source.zip`；支持可选择通话采集/系统 AcousticEchoCanceler 的测试候选版。Android 版本与 Windows 版本并非完全同步的“全平台统一 1.0.1 正式版”。

## 工程目录

- `windows/` — Flutter Windows seed、原生 C++ 音频核心与 Windows 打包脚本。
- `android/` — Flutter Android seed、Kotlin 原生服务、构建脚本。
- `resources/` — 原有应用图标与 Android 图标素材。
- `engine/` — 说明可选/外部提供的授权 Flutter 定制引擎组件，不包含二进制 DLL。
- `licenses/` — 原项目附带的 Flutter engine 第三方许可说明。

## 构建说明

**Windows**：需要 Flutter 3.47.6、Visual Studio + CMake。原项目的 `windows/BUILD_PC.cmd` 锁定指定 Flutter 版本及引擎哈希，先生成原生音频程序和 Flutter UI，再生成便携包。但当前公开源码**不包含自定义 `engine/flutter_windows.dll`**，故打包最后阶段必须由项目所有者合法提供已校验的修订引擎，否则脚本按设计拒绝打包。不要将其误认为直接可构建出完整 Stable 便携版。

**Android**：需要 Flutter + Android SDK，执行 `android/BUILD_ANDROID.cmd` 可按原构建步骤尝试编译（未在本准备环境做实际 Android 构建）。Android `AcousticEchoCanceler` 的存在/启用不保证真实环境降回声效果。

## 安全与隐私

Android 端申请麦克风、网络、前台服务权限。**该项目会处理实时麦克风数据并向局域网发送音频，使用前请明确告知用户。**公开发行前应独立审核流量保护、端口访问控制、隐私告知及权限最小化；目前不保证局域网流量加密或未经授权访问保护完备。

## 源码授权

Public 表示 GitHub 上所有人可以看见源码，不自动构成 MIT/GPL 等开源授权。项目级 LICENSE 尚未由所有者决定；第三方 Flutter 引擎有自己的许可和上游权利声明。公开前请审查 `PUBLISH_CHECKLIST.md`。

**项目状态**：Windows 1.0.1 为特定环境修复候选；Android AEC 为测试候选，不能保证所有设备稳定、延迟或无障碍行为。
