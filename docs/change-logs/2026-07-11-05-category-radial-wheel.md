# 记账分类径向轮盘

## 目的

降低长按分类后的浏览与滚动成本，将列表面板调整为可直接点击的设计化径向轮盘。

## 影响文件

- `FlashCount/Views/Components/CategoryPickerComponents.swift`
- `docs/change-logs/2026-07-11-05-category-radial-wheel.md`

## 行为变化

- 分类长按触发时间由 0.28 秒缩短为 0.22 秒。
- 长按后在屏幕中央展开圆形轮盘，不再展示需要滚动的长列表。
- 轮盘中心为大类入口，显示大类图标、名称和“使用大类”提示。
- 所有子类均以环形扇区排列，每个扇区显示图标与名称并可直接点击。
- 当前选中的大类或子类通过更清晰的描边与色彩强调。
- 点击轮盘外区域可关闭；保留 VoiceOver 标签与辅助功能减弱动态效果支持。
- 入场动画采用整盘缩放与轻微旋转，不使用逐项延迟、模糊或大面积重绘动画。

## 验证

- `git diff --check -- FlashCount/Views/Components/CategoryPickerComponents.swift` 通过。
- `xcodebuild -project FlashCount.xcodeproj -scheme FlashCount -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` 构建通过。

## 剩余限制

- 自定义分类数量非常多时，单个扇区的文字空间会随数量增加而缩小；当前通过两行文字和缩放下限缓解。
- 120Hz 真机上的动画节奏与扇区点击手感仍需实际设备最终验收。
