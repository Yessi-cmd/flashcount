import Foundation

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

struct DataHealthApplyResult {
    let actionCount: Int
    let remainingManualIssueCount: Int
}
