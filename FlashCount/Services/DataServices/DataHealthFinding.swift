import Foundation

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
