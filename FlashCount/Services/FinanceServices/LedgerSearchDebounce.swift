import Foundation

/// 防抖任务完成后只允许仍然代表当前输入的结果回写。
enum LedgerSearchQueryGate {
    static func accepts(query: String, latestQuery: String, isCancelled: Bool) -> Bool {
        !isCancelled && query == latestQuery
    }
}
