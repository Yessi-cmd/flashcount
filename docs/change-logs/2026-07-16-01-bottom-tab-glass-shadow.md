# 底部标签栏玻璃阴影对齐修复

## 目的

修复 iOS 26 真机上底部标签栏图标、选中态与阴影明显错位的问题。根因包括系统原生空 TabBar 未被完整隐藏，以及自定义 Tab 分别使用 Liquid Glass 后产生的方向性投影与融合。

## 影响文件

- `FlashCount/Views/MainTabView.swift`
- `FlashCountUITests/FlashCountSmokeTests.swift`
- `docs/change-logs/2026-07-16-01-bottom-tab-glass-shadow.md`

## 行为变化

- 在每个 `TabView` 页面上明确隐藏系统 TabBar，移除自定义底栏后方重复出现的原生空玻璃栏及多余 accessibility tab 节点。
- iOS 26 自定义底栏改为单一系统超薄材质基底和轻量同心阴影；页面内其他导航与控制仍保留原生 Liquid Glass。
- 普通 Tab 的选中态改为材质基底内的轻量色层与描边，不再切换 `.clear` / `.regular` 玻璃材质。
- 中央“记一笔”按钮改为基底内的实体强调按钮，保留按压和符号动画，但不再产生独立玻璃投影。
- 选中弹簧动画仅作用于图标缩放，避免玻璃材质和合成边界参与插值。
- 为五个底部控件增加稳定的 accessibility identifier，并加入切换前后按钮高度、纵向位置、frame 稳定性及唯一选中态回归断言。
- iOS 17–25 的旧版标签栏布局保持不变。

## 验证

- XcodeBuildMCP 的 iOS 26.2 模拟器 Debug 编译通过，无警告或错误。
- `xcodebuild build-for-testing` 通过，主 App、单元测试与 UI 测试包均成功生成。
- 定向 `testMainTabBarSelectionKeepsControlsAligned` UI 测试通过：`1` 项通过、`0` 项失败。
- iOS 26.2 模拟器逐个切换账本、预算、报表和资产页并截图验收；四个选中态的图标、色层和底栏阴影均保持同心，未再出现第二条空 TabBar。
- 修复前 UI 树包含额外的 `5` 个系统 tab 节点；修复后仅保留 `5` 个带稳定 identifier 的自定义按钮。
- 完整测试套件通过：`83` 项通过、`0` 项失败、`0` 项跳过，其中 `8` 项 UI 测试、`75` 项单元测试。
- `git diff --check` 通过。
- 使用 `scripts/package-altstore.sh` 重新生成 `build/FlashCount-AltStore.ipa`；版本为 `1.3.0 (3)`，大小为 `1,802,354` 字节，SHA-256 为 `44d3c340d3613e2da4a5cf2c47375e9e55b614244a1f20b76ce807577cc09481`。
- 独立解包审计通过：ZIP 完整，`Payload` 仅包含一个主 App，严格为 `arm64` 且完全未签名；无 Widget、扩展、签名、provisioning profile、私有数据、本机路径、模拟器路径或 macOS 元数据。
- XcodeGen 后 `FlashCount.xcodeproj/project.pbxproj` 无差异，SHA-256 保持 `4f5fd32988735834f47eeadf1d31d79f4895164751f319b18b68b16d40303905`；`build/` 中仅有一个规范命名的 IPA。

## 剩余限制

- iOS 26 自定义底栏刻意不直接使用 `glassEffect`，因为该 API 的系统方向性投影不可单独关闭；其他适合悬浮投影的导航控制仍使用 Liquid Glass。
