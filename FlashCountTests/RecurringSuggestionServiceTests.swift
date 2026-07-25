import XCTest
@testable import FlashCount

@MainActor
final class RecurringSuggestionServiceTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testDetectsMonthlyMonthEndPatternAndCalculatesNextDueDate() throws {
        let category = Category(name: "固定服务", icon: "repeat", colorHex: "#123456")
        let transactions = [
            transaction(on: (2026, 1, 31), amount: 30, note: "视频会员", category: category),
            transaction(on: (2026, 2, 28), amount: 30, note: " 视频会员 ", category: category),
            transaction(on: (2026, 3, 31), amount: 30, note: "视频会员", category: category),
        ]

        let suggestions = RecurringSuggestionService.suggestions(
            transactions: transactions,
            existingRules: [],
            referenceDate: date(2026, 4, 5),
            calendar: calendar
        )

        let suggestion = try XCTUnwrap(suggestions.first)
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestion.frequency, .monthly)
        XCTAssertEqual(suggestion.amount, 30)
        XCTAssertEqual(suggestion.occurrenceCount, 3)
        XCTAssertTrue(calendar.isDate(suggestion.nextDueDate, inSameDayAs: date(2026, 4, 30)))
    }

    func testValueInputProducesTheSameSuggestionAsModelAdapter() throws {
        let category = Category(name: "固定服务", icon: "repeat", colorHex: "#123456")
        let transactions = [
            transaction(on: (2026, 1, 10), amount: 30, note: "视频会员", category: category),
            transaction(on: (2026, 2, 10), amount: 30, note: "视频会员", category: category),
            transaction(on: (2026, 3, 10), amount: 30, note: "视频会员", category: category)
        ]
        let input = RecurringSuggestionInput(
            transactions: transactions.map {
                RecurringSuggestionTransactionInput(
                    amount: $0.amount,
                    date: $0.date,
                    note: $0.note,
                    isExpense: $0.isExpense,
                    recurringRuleID: $0.recurringRule?.id,
                    categoryID: $0.category?.id,
                    categoryName: $0.category?.name,
                    categoryIsArchived: $0.category?.isArchived ?? false,
                    ledgerID: $0.ledger?.id
                )
            },
            existingRules: []
        )

        let fromModels = RecurringSuggestionService.suggestions(
            transactions: transactions,
            existingRules: [],
            referenceDate: date(2026, 3, 11),
            calendar: calendar
        )
        let fromValueInput = RecurringSuggestionService.suggestions(
            input: input,
            referenceDate: date(2026, 3, 11),
            calendar: calendar
        )

        XCTAssertEqual(fromValueInput, fromModels)
    }

    func testDetectsWeeklyPatternWithSmallDateTolerance() throws {
        let category = Category(name: "通勤", icon: "tram", colorHex: "#123456")
        let transactions = [
            transaction(on: (2026, 6, 1), amount: 20, note: "周票", category: category),
            transaction(on: (2026, 6, 8), amount: 20, note: "周票", category: category),
            transaction(on: (2026, 6, 16), amount: 20, note: "周票", category: category),
        ]

        let suggestion = try XCTUnwrap(RecurringSuggestionService.suggestions(
            transactions: transactions,
            existingRules: [],
            referenceDate: date(2026, 6, 17),
            calendar: calendar
        ).first)

        XCTAssertEqual(suggestion.frequency, .weekly)
        XCTAssertTrue(calendar.isDate(suggestion.nextDueDate, inSameDayAs: date(2026, 6, 23)))
    }

    func testRejectsInconsistentMonthlyDates() {
        let category = Category(name: "固定服务", icon: "repeat", colorHex: "#123456")
        let transactions = [
            transaction(on: (2026, 1, 10), amount: 50, note: "会员", category: category),
            transaction(on: (2026, 2, 10), amount: 50, note: "会员", category: category),
            transaction(on: (2026, 3, 20), amount: 50, note: "会员", category: category),
        ]

        XCTAssertTrue(RecurringSuggestionService.suggestions(
            transactions: transactions,
            existingRules: [],
            referenceDate: date(2026, 3, 21),
            calendar: calendar
        ).isEmpty)
    }

    func testRejectsVariableAmountsOutsideFivePercentTolerance() {
        let category = Category(name: "固定服务", icon: "repeat", colorHex: "#123456")
        let transactions = [
            transaction(on: (2026, 1, 10), amount: 100, note: "云服务", category: category),
            transaction(on: (2026, 2, 10), amount: 120, note: "云服务", category: category),
            transaction(on: (2026, 3, 10), amount: 101, note: "云服务", category: category),
        ]

        XCTAssertTrue(RecurringSuggestionService.suggestions(
            transactions: transactions,
            existingRules: [],
            referenceDate: date(2026, 3, 11),
            calendar: calendar
        ).isEmpty)
    }

    func testSuppressesPatternCoveredByExistingRule() {
        let category = Category(name: "固定服务", icon: "repeat", colorHex: "#123456")
        let transactions = [
            transaction(on: (2026, 1, 10), amount: 30, note: "视频会员", category: category),
            transaction(on: (2026, 2, 10), amount: 30, note: "视频会员", category: category),
            transaction(on: (2026, 3, 10), amount: 30, note: "视频会员", category: category),
        ]
        let rule = RecurringRule(
            title: "视频会员",
            amount: 30,
            frequency: .monthly,
            nextDueDate: date(2026, 4, 10),
            category: category
        )

        XCTAssertTrue(RecurringSuggestionService.suggestions(
            transactions: transactions,
            existingRules: [rule],
            referenceDate: date(2026, 3, 11),
            calendar: calendar
        ).isEmpty)
    }

    func testGeneratedTransactionsDoNotBecomeSuggestions() {
        let category = Category(name: "固定服务", icon: "repeat", colorHex: "#123456")
        let rule = RecurringRule(title: "会员", amount: 30, nextDueDate: date(2026, 4, 10), category: category)
        let transactions = [
            Transaction(amount: 30, note: "会员", date: date(2026, 1, 10), category: category, recurringRule: rule),
            Transaction(amount: 30, note: "会员", date: date(2026, 2, 10), category: category, recurringRule: rule),
            Transaction(amount: 30, note: "会员", date: date(2026, 3, 10), category: category, recurringRule: rule),
        ]

        XCTAssertTrue(RecurringSuggestionService.suggestions(
            transactions: transactions,
            existingRules: [],
            referenceDate: date(2026, 3, 11),
            calendar: calendar
        ).isEmpty)
    }

    func testDismissalPersistsAndFiltersSuggestion() throws {
        let suiteName = "RecurringSuggestionServiceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "dismissed"
        let store = UserDefaultsRecurringSuggestionDismissalStore(userDefaults: defaults, key: key)
        let category = Category(name: "固定服务", icon: "repeat", colorHex: "#123456")
        let transactions = [
            transaction(on: (2026, 1, 10), amount: 30, note: "视频会员", category: category),
            transaction(on: (2026, 2, 10), amount: 30, note: "视频会员", category: category),
            transaction(on: (2026, 3, 10), amount: 30, note: "视频会员", category: category),
        ]
        let original = try XCTUnwrap(RecurringSuggestionService.suggestions(
            transactions: transactions,
            existingRules: [],
            referenceDate: date(2026, 3, 11),
            calendar: calendar
        ).first)

        store.dismiss(original.fingerprint)
        let reloaded = UserDefaultsRecurringSuggestionDismissalStore(userDefaults: defaults, key: key).load()

        XCTAssertTrue(reloaded.contains(original.fingerprint))
        XCTAssertTrue(RecurringSuggestionService.suggestions(
            transactions: transactions,
            existingRules: [],
            dismissedFingerprints: reloaded,
            referenceDate: date(2026, 3, 11),
            calendar: calendar
        ).isEmpty)
    }

    private func transaction(
        on components: (Int, Int, Int),
        amount: Decimal,
        note: String,
        category: FlashCount.Category
    ) -> Transaction {
        Transaction(
            amount: amount,
            note: note,
            date: date(components.0, components.1, components.2),
            category: category
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}
