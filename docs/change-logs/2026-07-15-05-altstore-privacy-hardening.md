# AltStore 打包隐私加固

## 目的

阻止 Release 代码覆盖率映射把本机源码绝对路径写入 AltStore 主程序，并把完全未签名、严格架构和隐私内容检查前移到 IPA 原子替换之前。

## 影响文件

- `scripts/package-altstore.sh`
- `docs/packaging.md`
- `docs/change-logs/2026-07-15-05-altstore-privacy-hardening.md`

## 行为变化

- Release 真机构建明确关闭 Swift/Clang/GCC 代码覆盖率与覆盖率映射。
- IPA 暂存主程序在无签名状态下移除调试符号和本地符号，避免无签名普通构建跳过最终剥离步骤。
- 打包脚本要求主程序架构严格等于 `arm64`，不再只检查是否包含 `arm64`。
- 打包脚本通过 `codesign -dvvv` 的明确诊断确认 App 完全未签名，拒绝残缺签名状态。
- 在替换旧 IPA 前扫描本机项目路径、签名或 provisioning 标识，以及 SQLite、CSV、备份等运行时或导出数据。

## 验证

- `bash -n scripts/package-altstore.sh` 与 `git diff --check` 通过。
- 使用加固后的脚本重新生成 `build/FlashCount-AltStore.ipa`；当前最终包版本为 `1.3.0 (3)`，IPA 大小为 `1,802,354` 字节，SHA-256 为 `44d3c340d3613e2da4a5cf2c47375e9e55b614244a1f20b76ce807577cc09481`。
- 独立解包复核通过：ZIP 完整，`Payload` 仅包含一个 `FlashCount.app`，主程序严格为 `arm64`，且 `codesign -dvvv` 确认完全未签名。
- 未发现 Widget、`.appex`、`PlugIns`、`_CodeSignature`、`CodeResources`、`embedded.mobileprovision`、运行时或导出数据、沙盒目录、macOS 元数据、本机路径、模拟器路径及签名或 provisioning 标识。
- Bundle ID 为 `com.flashcount.app`，目标平台为 `iPhoneOS`；`build/` 中仅有规范命名的 AltStore IPA，没有旧版或带版本后缀的 IPA 副本。
- `FlashCount.xcodeproj/project.pbxproj` 无差异，SHA-256 仍为 `4f5fd32988735834f47eeadf1d31d79f4895164751f319b18b68b16d40303905`，确认 XcodeGen 未产生非预期工程变更。

## 剩余限制

- 静态扫描只能识别已定义的敏感标识和文件类型；发布前仍需保留人工解包复核。
