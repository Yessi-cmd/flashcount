# GitHub 社区资料与 1.4.3 发布

## 目的

完善仓库的开源授权、项目入口和协作资料，并将已验证的 1.4.3 AltStore 包发布到 GitHub Releases。

## 影响文件

- `README.md`
- `LICENSE`
- `CONTRIBUTING.md`
- `SECURITY.md`
- `CODE_OF_CONDUCT.md`
- `.github/ISSUE_TEMPLATE/bug_report.yml`
- `.github/ISSUE_TEMPLATE/feature_request.yml`
- `.github/ISSUE_TEMPLATE/config.yml`
- `.github/PULL_REQUEST_TEMPLATE.md`
- `docs/change-logs/2026-07-25-13-github-community-and-release.md`

## 行为变化

- README 使用正确的仓库克隆地址，并新增 CI、Release、许可证入口、安装方式、开发命令、隐私说明和贡献入口。
- 明确以 MIT License 发布项目。
- GitHub 新增 Bug/功能建议表单、PR 模板、贡献指南、行为准则和私密安全报告说明。
- 1.4.3 Release 附带仅含未签名主 App 的 `FlashCount-AltStore.ipa`，由 AltStore 在安装时重新签名。

## 验证

- 核验 `build/FlashCount-AltStore.ipa` 的 SHA-256 为 `e00dc6ab2bd2bb56f26419d3258640c7b9ef5e7a1796976249101621f4ee889f`。
- IPA ZIP 完整性通过；仅含 `Payload/FlashCount.app`，没有 Widget、`.appex`、`PlugIns/`、`_CodeSignature` 或 `embedded.mobileprovision`。
- IPA 元数据为 `com.flashcount.app`、版本 `1.4.3`、构建号 `7`。
- GitHub Actions 的 `main` 最新 CI 构建和测试通过。

## 剩余限制

- `FlashCount-AltStore.ipa` 仅供 AltStore 重新签名安装，不是 App Store、TestFlight 或开发签名分发包。
- 私密安全报告依赖 GitHub Private Vulnerability Reporting 保持启用；若仓库迁移或该功能关闭，需同步更新 `SECURITY.md` 与 Issue 配置。
