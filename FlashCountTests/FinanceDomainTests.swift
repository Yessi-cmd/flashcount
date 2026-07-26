import XCTest
import SwiftData
@testable import FlashCount

/// 财务域回归测试：核心类与共享测试工具。
/// 具体域的测试按 extension 分布在：
/// - `FinanceDomainTests+Migration.swift`（提醒迁移与 Schema 升级）
/// - `FinanceDomainTests+Backup.swift`（备份导入导出）
/// - `FinanceDomainTests+Budget.swift`（发薪周期、预算与日常额度）
/// - `FinanceDomainTests+Recurring.swift`（周期规则与 CSV 导入）
@MainActor
final class FinanceDomainTests: XCTestCase {
    var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    // MARK: - 金额与展示策略

    func testCodableMoneyRejectsInvalidStrings() {
        XCTAssertThrowsError(try JSONDecoder().decode(CodableMoney.self, from: Data("\"not-money\"".utf8)))
    }

    func testMoneyValidationAndModelsClampInvalidProgress() {
        XCTAssertFalse(MoneyValidation.nonNegative(-1))
        XCTAssertFalse(MoneyValidation.validPhysicalAsset(purchasePrice: 100, salvageValue: 101, targetDailyCost: 1))

        let goal = SavingsGoal(name: "应急金", targetAmount: 100, currentAmount: -20)
        XCTAssertEqual(goal.currentAmount, 0)
        XCTAssertEqual(goal.progress, 0)

        let liability = Asset(name: "信用卡", type: .creditCard, balance: -100)
        XCTAssertEqual(liability.balance, 0)
        XCTAssertEqual(liability.signedBalance, 0)
    }

    func testLedgerPeriodFiltersDistinguishTodayMonthAndPayCycle() throws {
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 12)))
        let customStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 2)))
        let customEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 4)))

        let today = try XCTUnwrap(LedgerPeriodFilter.today.dateRange(
            referenceDate: date, payday: 25, customStart: customStart, customEnd: customEnd, calendar: calendar
        ))
        let month = try XCTUnwrap(LedgerPeriodFilter.thisMonth.dateRange(
            referenceDate: date, payday: 25, customStart: customStart, customEnd: customEnd, calendar: calendar
        ))
        let cycle = try XCTUnwrap(LedgerPeriodFilter.payCycle.dateRange(
            referenceDate: date, payday: 25, customStart: customStart, customEnd: customEnd, calendar: calendar
        ))

        XCTAssertEqual(calendar.component(.day, from: today.lowerBound), 11)
        XCTAssertEqual(calendar.component(.day, from: today.upperBound), 12)
        XCTAssertEqual(calendar.component(.day, from: month.lowerBound), 1)
        XCTAssertEqual(calendar.component(.month, from: month.upperBound), 8)
        XCTAssertEqual(calendar.component(.day, from: cycle.lowerBound), 25)
        XCTAssertEqual(calendar.component(.month, from: cycle.lowerBound), 6)
        XCTAssertEqual(LedgerPeriodFilter.payCycle.metricPrefix, "本周期")
        XCTAssertEqual(LedgerPeriodFilter.thisMonth.metricPrefix, "本月")
    }

    // MARK: - 隐私展示策略

    func testPrivacyPolicyUsesOneUnlockStateForIncomeAndAssets() {
        XCTAssertFalse(PrivacyVisibilityPolicy.hidesIncome(isExpense: true, isUnlocked: false))
        XCTAssertTrue(PrivacyVisibilityPolicy.hidesIncome(isExpense: false, isUnlocked: false))
        XCTAssertFalse(PrivacyVisibilityPolicy.hidesIncome(isExpense: false, isUnlocked: true))

        XCTAssertTrue(PrivacyVisibilityPolicy.hidesAssets(isUnlocked: false))
        XCTAssertFalse(PrivacyVisibilityPolicy.hidesAssets(isUnlocked: true))
    }

    func testPrivacyPolicyOnlyHidesProtectedIncomeMetadataWhileLocked() {
        XCTAssertFalse(PrivacyVisibilityPolicy.hidesProtectedMetadata(isProtectedIncome: false, isUnlocked: false))
        XCTAssertTrue(PrivacyVisibilityPolicy.hidesProtectedMetadata(isProtectedIncome: true, isUnlocked: false))
        XCTAssertFalse(PrivacyVisibilityPolicy.hidesProtectedMetadata(isProtectedIncome: true, isUnlocked: true))
    }

    /// 请求显示会直接进生物识别（中间那次「确认」弹窗已经去掉），
    /// 但在验证成功之前一个字都不能露出来——这条才是隐私锁的安全性所在。
    func testPrivacyRevealStaysLockedUntilAuthenticationSucceeds() {
        let privacyLock = PrivacyLockService()

        XCTAssertFalse(privacyLock.isUnlocked)

        privacyLock.requestReveal()
        XCTAssertFalse(privacyLock.isUnlocked, "验证尚未完成时不能提前解锁")

        privacyLock.lock()
        XCTAssertFalse(privacyLock.isUnlocked)
    }

    // MARK: - 共享测试工具

    func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Transaction.self,
            Category.self,
            Ledger.self,
            RecurringRule.self,
            Budget.self,
            PhysicalAsset.self,
            CashPoolItem.self,
            CashPoolState.self,
            SavingsGoal.self,
            InstallmentBill.self,
            TransactionTemplate.self,
            Reminder.self,
            RecurringOccurrence.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    var legacyModelTypes: [any PersistentModel.Type] {
        [
            Transaction.self,
            Category.self,
            Ledger.self,
            RecurringRule.self,
            Budget.self,
            PhysicalAsset.self,
            CashPoolItem.self,
            CashPoolState.self,
            SavingsGoal.self,
            InstallmentBill.self,
            TransactionTemplate.self
        ]
    }

    func assertReminder(
        _ actual: ReminderItem,
        matches expected: ReminderItem,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.id, expected.id, file: file, line: line)
        XCTAssertEqual(actual.title, expected.title, file: file, line: line)
        XCTAssertEqual(actual.note, expected.note, file: file, line: line)
        XCTAssertEqual(actual.intensity, expected.intensity, file: file, line: line)
        XCTAssertEqual(actual.isCompleted, expected.isCompleted, file: file, line: line)
        XCTAssertEqual(actual.dueDate.timeIntervalSince1970, expected.dueDate.timeIntervalSince1970, accuracy: 1, file: file, line: line)
        XCTAssertEqual(actual.createdAt.timeIntervalSince1970, expected.createdAt.timeIntervalSince1970, accuracy: 1, file: file, line: line)
        switch (actual.completedAt, expected.completedAt) {
        case (nil, nil):
            break
        case let (.some(actualDate), .some(expectedDate)):
            XCTAssertEqual(
                actualDate.timeIntervalSince1970,
                expectedDate.timeIntervalSince1970,
                accuracy: 1,
                file: file,
                line: line
            )
        default:
            XCTFail("completedAt 不一致", file: file, line: line)
        }
    }

    func temporaryFile(named name: String, contents: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlashCountTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, options: .atomic)
        return url
    }
}
