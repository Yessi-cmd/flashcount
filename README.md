# FlashCount ⚡

[![iOS CI](https://github.com/Yessi-cmd/flashcount/actions/workflows/ios-ci.yml/badge.svg)](https://github.com/Yessi-cmd/flashcount/actions/workflows/ios-ci.yml)
[![Latest release](https://img.shields.io/github/v/release/Yessi-cmd/flashcount?display_name=tag)](https://github.com/Yessi-cmd/flashcount/releases)
[![License](https://img.shields.io/github/license/Yessi-cmd/flashcount)](LICENSE)

**开源、本地优先的 iOS 记账 App。** 数据保存在设备上；不依赖账户、云端同步、广告或追踪。

> 仍在持续开发中。欢迎提交问题、建议和改进。

## 功能

| 功能 | 说明 |
| --- | --- |
| ⚡ 快速记账 | 支出、收入、分类、备注和模板，金额可用「+」累加拆账，保存后可撤销；输入金额时实时显示今日/本周期预算；支持 Siri、Back Tap 与快捷指令入口。 |
| 📒 单账本 | 将收支、预算、资产、分期和提醒集中到一个个人生活账本。 |
| 🔄 周期与订阅 | 周期规则可在启动时生成到期交易并提示补记；订阅采用提醒优先，确认续费后才推进日期并默认写入支出。 |
| 📊 预算与报表 | 追踪日常及分类预算，按日、周、月、年和发薪周期查看收支和趋势，数字可下钻到对应交易。 |
| 💰 资产全景 | 资金池、储蓄目标、实物资产与分期负债各自成账；现金流预测将已知账单与历史日常支出分开，展示未来余额的常见区间而非一条假装精确的线。净资产只按资金池口径统计（实物估值与储蓄目标不计入）。 |
| 🛡️ 本地隐私 | 所有账本数据留在设备本地；不含广告、分析 SDK 或网络请求。 |
| 🎨 个性化外观 | 森林绿、海洋蓝、紫罗兰、玫瑰和石墨灰多套强调色，搭配对应的 App 图标。 |

## 系统要求

- iOS 17.0 或更高版本
- Xcode 26 或更高版本（从源码构建；CI 持续验证的即为最新稳定版 Xcode。代码保留了针对旧 SDK 的编译回退，但不再逐版验证）
- Swift 5.9

## 安装与运行

### 从 Release 安装

最新版本在 [GitHub Releases](https://github.com/Yessi-cmd/flashcount/releases) 发布。若 Release 附有 `FlashCount-AltStore.ipa`，请使用 AltStore 安装；该包是未签名主 App，由 AltStore 在安装时重新签名。

#### AltStore 到期与本地数据

AltStore 的签名到期通常只会让 App 暂时无法启动，不会清除 FlashCount 的本地账本。重新安装 AltStore 时，不要先从 iPhone 删除 AltStore 或 FlashCount；安装完成后在 AltStore 中刷新 FlashCount。

FlashCount 的账本页默认显示“本周期”。如果刷新后恰逢新的发薪周期开始，页面可能显示“暂无交易记录”，但历史数据仍在。先把日期范围切换到“全部”或“本月”确认，再考虑任何恢复操作。不要通过卸载重装来排查数据问题。

### 从源码构建

```bash
git clone https://github.com/Yessi-cmd/flashcount.git
cd flashcount

# 安装并使用 XcodeGen 生成工程
brew install xcodegen
./scripts/generate-project.sh

# 用 Xcode 打开，选择模拟器或你的签名团队后运行
open FlashCount.xcodeproj
```

## 开发

```bash
# 生成工程（脚本会补上本机私有的 project.local.yml；直接跑 xcodegen generate
# 在没有该文件的机器上会失败，XcodeGen 的 include 不支持可选）
./scripts/generate-project.sh

# 在已安装的 iOS Simulator 上运行测试
xcodebuild test \
  -project FlashCount.xcodeproj \
  -scheme FlashCount \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

GitHub Actions 会在 `main` 的推送与 Pull Request 上重新生成工程并运行测试。提交前请阅读[贡献指南](CONTRIBUTING.md)和[安全政策](SECURITY.md)。

## 隐私

- 账本数据、备份和偏好设置均在本地保存。
- 应用不要求注册账户，也不发送使用分析数据。
- 备份、CSV 导入导出和提醒由设备本地处理。
- 建议定期从设置中导出完整 JSON 备份，尤其是在卸载 App、更换设备或调整侧载方式之前。

完整的发布包规则见[打包规范](docs/packaging.md)。

## 参与贡献

请先阅读[贡献指南](CONTRIBUTING.md)和[行为准则](CODE_OF_CONDUCT.md)，再通过 Issue 或 Pull Request 参与。安全漏洞请不要公开提交 Issue，详见[安全政策](SECURITY.md)。

## License

本项目采用 [MIT License](LICENSE)。
