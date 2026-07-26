# BLOCKERS

无法在当前条件下完成的项，附事实与原因。

## 覆盖率 85% 的总量目标对本仓库形状不成立（2026-07-27）

实测基线（`xcodebuild test -enableCodeCoverage YES` + `xccov`）：

| 层 | 覆盖率 | 可执行行 |
| --- | --- | --- |
| `Models/` | 88.7% | 767 |
| `Services/BudgetServices` | 89.2% | 582 |
| `Services/FinanceServices` | 83.8% | 3486 |
| `Core/` | 81.4% | 709 |
| `Services/SystemServices` | 80.3% | 842 |
| `Services/DataServices` | 78.1% | 2671 |
| **以上逻辑层合计** | **≈82.6%** | **9057** |
| `Views/` 合计 | ≈29% | 41155 |
| 全目标 | **43.24%** | 51542 |

问题在分母：**约 80% 的计数行是 SwiftUI 视图代码**（41155 / 51542），其中 `Views/VisualExploration`
（3143 行，0%）是 DEBUG-only 设计实验室，Release 二进制里根本不存在，却照样计入分母。

要把总量推到 85%，等于必须覆盖几乎全部视图 body，只有两条路：

1. 写数百个 UI 测试。当前 22 个 UI 测试跑一轮约 4.5 分钟，且本身不稳定——这次带覆盖率的运行
   就出现一次 `Failed to get launch progress ... No bundle identifier was specified` 的伪失败
   （同一份代码不带覆盖率跑是全绿的）。数百个这种测试会让测试套件既慢又不可信。
2. 写只为实例化 view body 的"测试"。这能把数字推上去，但不检出任何缺陷——是在优化指标，
   不是在改进项目。

因此本轮采取的实际目标：**逻辑层（Models / Services / Core）覆盖率持续推高，视图层只为关键
流程补 UI 冒烟测试**。总量数字会因此停在 45–55% 区间，这个数字反映的是代码构成，不是测试质量。

如果确实需要一个可作为门禁的覆盖率数字，建议改为按 target/目录设阈值（例如逻辑层 ≥85%、
视图层不设或设 30%），并把 `VisualExploration` 排除在统计外。这需要人来决定，不由 agent 单方面改。

## UI 测试在启用覆盖率时偶发启动失败（2026-07-27）

`testChangeSubcategoryButtonOpensWheel` 在 `-enableCodeCoverage YES` 的运行里失败于
`Invalid request: No bundle identifier was specified`，1.6 秒即失败（正常约 16 秒），
不带覆盖率重跑全绿。属于 xcodebuild/模拟器启动的环境问题，非测试或产品缺陷。
若在 CI 上复现，考虑给 UI 测试加重试，或把覆盖率统计限定在单元测试目标上。
