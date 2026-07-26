# IPA 打包规范

## 目标

- `build/` 中每个分发渠道只保留一个 IPA。
- 使用稳定、可预测的文件名，重新打包时更新原文件。
- 在产物替换和对外发布前完成结构、签名和隐私检查。

## 固定命名

| 分发渠道 | 唯一文件名 | 要求 |
|---|---|---|
| AltStore | `build/FlashCount-AltStore.ipa` | 未签名，仅包含主 App，由 AltStore 重签名 |
| 正式分发 | `build/FlashCount.ipa` | 仅在明确指定 App Store、TestFlight 或其他分发方式时生成 |

禁止在 IPA 文件名中添加版本号、构建号、日期、`final`、`new` 或数字副本后缀。版本信息以 App 的 `Info.plist` 和 GitHub Release 标签为准。

`build/` 最多保留上述两个 IPA；只打包一种渠道时，只保留当前需要的一个。归档、DerivedData、临时 Payload 和打包日志放在 `/tmp`，不在项目中堆积。

## AltStore 打包

在仓库根目录执行：

```bash
./scripts/package-altstore.sh
```

脚本会：

1. 从 `project.yml` 重新生成 Xcode 工程。
2. 对真机 `arm64` 构建全新的未签名 Release App。
3. 明确关闭代码覆盖率，避免覆盖率映射把本机源码绝对路径写入主程序。
4. 防御性移除任何 `PlugIns/` 扩展目录（项目自 2026-07 起已不含 Widget 扩展，此步通常为空操作）。
5. 移除 `_CodeSignature`、`embedded.mobileprovision`、调试符号和本地符号，交由 AltStore 安装时重签名。
6. 验证 ZIP 完整性、严格 `arm64` 架构、完全未签名状态、本机路径、签名标识和运行时数据等禁止内容。
7. 所有检查通过后，原子替换 `build/FlashCount-AltStore.ipa`。失败时保留上一个可用产物。
8. 删除 `build/` 中不符合两个固定名称的旧 IPA 副本。

AltStore 包不包含任何扩展，避免额外 App ID 和扩展重签名造成安装卡住。

## 发布前检查

- IPA 可被完整解压，Payload 中只有预期的 App。
- AltStore 包不得包含 `.appex`、`PlugIns/`、`_CodeSignature/` 或 `embedded.mobileprovision`。
- AltStore 包的主 App 必须是未签名状态；未签名是预期行为。
- 不得包含 SwiftData/SQLite 运行时数据、备份、CSV 导出或个人账本数据。
- 主程序不得包含本机项目绝对路径；Release 打包必须关闭代码覆盖率。
- 不得将开发签名 IPA 用于公开下载，因为其 provisioning profile 可能包含团队、证书和设备 UDID。
- 上传 GitHub Release 前必须再次执行上述检查，并获得明确的发布授权。

## 产物交付

交付时只提供固定文件名、App 版本/构建号、文件大小和 SHA-256。不另外复制或改名 IPA。
