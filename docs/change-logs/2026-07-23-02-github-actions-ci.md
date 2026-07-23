# GitHub Actions iOS CI

## 目的

- 为 `main` 推送和面向 `main` 的 Pull Request 建立可重复的 iOS 构建与测试门禁。

## 受影响文件

- `.github/workflows/ios-ci.yml`

## 行为变化

- 工作流在 macOS 15 Runner 上按需安装 XcodeGen、由 `project.yml` 重新生成工程并验证生成结果没有漂移。
- 工作流在 iPhone 16 Pro 模拟器上以禁用代码签名的 Debug 配置运行完整 `FlashCount` 测试 scheme。
- 同一分支的新运行会取消旧运行，且工作流只读仓库内容，不使用部署密钥或发布权限。

## 验证

- 已在本地确认 `xcodegen generate` 和完整模拟器测试可用；本次提交后由 GitHub Actions 首次执行远端验证。

## 剩余限制

- GitHub Runner 上的模拟器名称和可用运行时由 GitHub 托管映像决定；若映像移除 iPhone 16 Pro，需更新工作流目的地。
