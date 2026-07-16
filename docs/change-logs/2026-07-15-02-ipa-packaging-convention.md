# IPA 打包产物规范

## 目的

收敛 IPA 产物数量和文件名，避免每次打包都产生带版本号、日期或副本后缀的新文件，并固化 AltStore 包的无签名、无 Widget 和隐私检查要求。

## 影响文件

- `AGENTS.md`
- `README.md`
- `docs/packaging.md`
- `scripts/package-altstore.sh`
- `docs/change-logs/2026-07-15-02-ipa-packaging-convention.md`

## 行为变化

- IPA 只使用 `build/FlashCount.ipa` 和 `build/FlashCount-AltStore.ipa` 两个固定名称，同渠道重新打包时替换原产物。
- 禁止在 IPA 文件名中添加版本号、构建号、日期或副本后缀。
- AltStore 打包改为统一脚本：全新编译未签名 Release 真机版，仅从 IPA 中移除 Widget、签名和 provisioning profile，验证通过后再替换固定产物并清理非规范命名的旧 IPA。
- 明确禁止公开发布开发签名 IPA，上传前必须检查设备标识和运行时数据。
- 当前本地 `build/` 中的多余 IPA 副本会被清理，只保留最新的 AltStore 固定产物。

## 验证

- `scripts/package-altstore.sh` 完整执行成功，Release 真机构建通过。
- IPA ZIP 完整性检查通过；主程序为 `arm64`、版本 1.3.0 (3)、未签名。
- 确认产物中没有 `.appex`、`PlugIns/`、`_CodeSignature/` 或 `embedded.mobileprovision`。
- 确认 `build/` 只保留 `FlashCount-AltStore.ipa`，SHA-256 为 `0f03fa27211e8c5dc12fbacf94a4163666da0b5662e1149aca43ce8b830d7bb8`。
- `bash -n scripts/package-altstore.sh` 和 `git diff --check` 通过。

## 剩余限制

- AltStore 包为了最大化重签名兼容性，不包含 Widget；正常 Xcode 和正式分发构建仍保留 Widget。
- 脚本只能验证 IPA 的静态结构，AltStore 服务器、Apple ID 配额和真机安装环境仍需在目标设备上确认。
