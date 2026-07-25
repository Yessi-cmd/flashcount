# 版本 1.4.3 与 AltStore 打包

## 目的

发布本批次 UI、性能与无障碍缺陷修复，并将应用版本更新为 1.4.3（构建号 7）。

## 影响文件

- `project.yml`
- `FlashCount.xcodeproj/project.pbxproj`（由 XcodeGen 重新生成）
- `docs/change-logs/2026-07-25-09-ui-performance-accessibility-remediation.md`
- `build/FlashCount-AltStore.ipa`（本地构建产物，按项目规则保持固定文件名）

## 行为变化

- `MARKETING_VERSION` 从 1.4.2 更新为 1.4.3。
- `CURRENT_PROJECT_VERSION` 从 6 更新为 7。
- 生成 AltStore 用未签名主 App 包；不包含 Widget、代码签名或 provisioning profile。
- 不改变本地数据格式、隐私策略或网络依赖。

## 验证结果

- `xcodegen generate` 成功。
- `scripts/package-altstore.sh` 完成并生成 `build/FlashCount-AltStore.ipa`。
- IPA `CFBundleShortVersionString=1.4.3`、`CFBundleVersion=7`、Bundle ID 为 `com.flashcount.app`。
- IPA 通过完整性检查，仅包含主 App，架构为 `arm64`；未发现 Widget、`_CodeSignature`、`embedded.mobileprovision` 或个人/开发者标识。
- `codesign` 检查确认 App 未签名；ZIP 测试通过。
- 产物大小为 2,274,414 bytes，SHA-256 为 `e00dc6ab2bd2bb56f26419d3258640c7b9ef5e7a1796976249101621f4ee889f`。

## 剩余限制

- 当前产物是 AltStore 规则要求的未签名 IPA，不是 App Store 发布包。
- 完整 UI 测试套件和正式 Instruments 5,000/10,000 笔性能基准不在本次打包验证范围内；详见上一批次变更日志。
