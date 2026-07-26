import Foundation

/// 一类问题的体检结论。
///
/// `count` 拆成 `repairableCount` + `manualCount` 是刻意的：能自动修的和
/// 只能人工判断的必须分开呈现，把两者混成一个数字会让用户以为点一下
/// 就全好了。`detail` 还要说明为什么某些情况不自动处理。
struct DataHealthFinding: Identifiable, Equatable {
    let kind: DataHealthIssueKind
    let count: Int
    let repairableCount: Int
    let manualCount: Int
    let detail: String

    var id: String { kind.id }

    var hasIssue: Bool { count > 0 }

    var statusText: String {
        if count == 0 { return "未发现" }
        if manualCount == 0 { return "可修复" }
        if repairableCount == 0 { return "需人工处理" }
        return "部分可修复"
    }
}
