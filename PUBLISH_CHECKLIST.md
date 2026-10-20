# 公开发布前检查

- [ ] 先审查全部源码是否包含密钥、设备 IP、个人信息和硬编码凭证
- [ ] 确认 Windows `engine/flutter_windows.dll` **不在 git 仓库**，公开包里只有说明；未来有授权、可重现方案后再决定分发
- [ ] 核对 Android RECORD_AUDIO / FOREGROUND_SERVICE_MICROPHONE 权限及网络隐私说明
- [ ] 在 Windows / Android 实机分别构建、运行和验收（本包未实测编译）
- [ ] 决定自有源码许可证，并审核第三方组件许可证
- [ ] 在 GitHub 创建空 Public 仓库 VoxLink，并手动审核初始提交
- [ ] 不将原始含 DLL 的 ZIP、DMP 崩溃转储或本地程序配置上传
