# 贡献指南

感谢你愿意改进 FlashCount。贡献前请先阅读本指南和[行为准则](CODE_OF_CONDUCT.md)。

## 提交 Issue

- 使用 Bug 或功能建议表单，提供可复现步骤、预期与实际结果。
- 请先搜索已有 Issue，避免重复。
- 不要在公开 Issue 中提交账本、备份、日志中的个人财务信息，或任何密钥、设备标识和签名文件。
- 安全漏洞请遵循[安全政策](SECURITY.md)。

## 本地开发

1. Fork 后克隆仓库：`git clone https://github.com/<your-account>/flashcount.git`
2. 安装 Xcode 15+ 与 XcodeGen：`brew install xcodegen`
3. 运行 `xcodegen generate`；请编辑 `project.yml`，不要直接编辑生成的 `FlashCount.xcodeproj/project.pbxproj`。
4. 使用模拟器运行应用和测试；涉及财务金额时使用 `Decimal`，并保持数据本地优先。

## Pull Request

- 每个 PR 聚焦一个可审阅的目标，并说明用户可见变化。
- 不要提交 `build/`、DerivedData、个人账本、备份、签名、provisioning profile 或设备标识。
- 添加或更新与修改行为相匹配的测试；执行相关单元/UI 测试，并在 PR 中列出命令与结果。
- 如果改动会影响隐私、备份兼容性或数据迁移，请在 PR 中单独说明。
- 为每一批完整代码改动，在 `docs/change-logs/` 添加变更记录，说明目的、影响文件、行为变化、验证与限制。

## 提交信息

使用简洁、可搜索的前缀，例如 `feat:`、`fix:`、`docs:`、`test:` 或 `chore:`。提交信息应说明意图，而不是只描述文件名。
