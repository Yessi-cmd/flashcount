import Foundation

/// 一次体检的结果：结论列表加可执行的修复方案。
///
/// `isHealthy` 与 `hasRepairableIssues` 是两件事——存在只能人工处理的问题时，
/// 数据不健康但没有可自动执行的动作。
struct DataHealthReport {
    let scannedAt: Date
    let findings: [DataHealthFinding]
    let plan: DataHealthRepairPlan

    var isHealthy: Bool {
        findings.allSatisfy { !$0.hasIssue }
    }

    var hasRepairableIssues: Bool {
        plan.hasChanges
    }

    var manualIssueCount: Int {
        findings.reduce(0) { $0 + $1.manualCount }
    }

    var totalIssueCount: Int {
        findings.reduce(0) { $0 + $1.count }
    }
}

/// 修复执行结果。`remainingManualIssueCount` 用来告诉用户还剩多少需要
/// 自己判断的问题，避免「修复完成」被理解为一切都已解决。
struct DataHealthApplyResult {
    let actionCount: Int
    let remainingManualIssueCount: Int
}
