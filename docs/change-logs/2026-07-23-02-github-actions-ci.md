# GitHub Actions iOS CI

## 目的

- 为 `main` 推送和面向 `main` 的 Pull Request 建立可重复的 iOS 构建与测试门禁。

## 受影响文件

- `.github/workflows/ios-ci.yml`

## 行为变化

- 工作流在 macOS 15 Runner 上按需安装 XcodeGen，并由 `project.yml` 重新生成构建所需工程。
- 工作流先安装与 Runner 上 Xcode 匹配的 iOS Simulator runtime，再动态选择可用的 iPhone 设备类型并创建专用模拟器。
- 工作流以禁用代码签名的 Debug 配置运行完整 `FlashCount` 测试 scheme，完成后删除临时模拟器。
- 同一分支的新运行会取消旧运行，且工作流只读仓库内容，不使用部署密钥或发布权限。

## 验证

- 已在本地确认 `xcodegen generate` 和完整模拟器测试可用；首次远端运行确认不同 XcodeGen 小版本会改变无功能的 `.pbxproj` 元数据，因此 CI 不再以字节级工程差异作为门禁，而以真实构建和测试作为验证。
- 已复核首次远端失败日志：工程生成成功，但 Runner 未预装 iOS Simulator runtime；在这种环境中，资产编译也不能完成，因此将 runtime 安装设为构建测试的前置条件。
- 第二次远端运行确认下载命令必须以 Actions 用户身份运行；以 `sudo` 运行时无法连接该用户的 Simulator 服务，现已改为原生命令。

## 剩余限制

- 首次下载 iOS Simulator runtime 会增加数 GB 网络传输和数分钟耗时；若 Apple 的下载服务不可用，CI 会明确在安装步骤失败。
