import Foundation
import Observation

/// 账本页的筛选、搜索与排序状态。集中在一个可观察对象里，
/// 避免视图层散落十几个 `@State` 并在多个文件间穿引。
@Observable
final class LedgerFilterState {
    var searchText = ""
    var debouncedSearchText = ""
    var dateFilter: LedgerPeriodFilter = .payCycle
    var customStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    var customEndDate = Date()

    var typeFilter: TransactionTypeFilter = .all
    var categoryFilterId: UUID?
    var minAmountText = ""
    var maxAmountText = ""
    var sortField: TransactionSortField = .date
    var sortDirection: TransactionSortDirection = .descending

    /// 是否有活跃的筛选条件（不计关键词搜索）
    var hasActiveFilters: Bool {
        typeFilter != .all
        || categoryFilterId != nil
        || (!minAmountText.isEmpty && (Decimal(string: minAmountText) ?? 0) > 0)
        || (!maxAmountText.isEmpty && (Decimal(string: maxAmountText) ?? 0) > 0)
    }

    /// 活跃筛选条件数量（不计关键词搜索）
    var activeFilterCount: Int {
        var count = 0
        if typeFilter != .all { count += 1 }
        if categoryFilterId != nil { count += 1 }
        if !minAmountText.isEmpty && (Decimal(string: minAmountText) ?? 0) > 0 { count += 1 }
        if !maxAmountText.isEmpty && (Decimal(string: maxAmountText) ?? 0) > 0 { count += 1 }
        return count
    }

    var hasCustomSort: Bool {
        sortField != .date || sortDirection != .descending
    }

    /// 清除高级筛选（类型/分类/金额区间），保留搜索与排序。
    func clearAdvancedFilters() {
        typeFilter = .all
        categoryFilterId = nil
        minAmountText = ""
        maxAmountText = ""
    }
}
