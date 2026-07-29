import SwiftData
import XCTest
@testable import FlashCount

final class LocalActionCenterDataStoreTests: XCTestCase {
    @MainActor
    func testBackgroundStoreCountsIncompleteReminder() async throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: FlashCountSchemaV3.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.insert(Reminder(item: ReminderItem(
            title: "待处理",
            dueDate: Date.now.addingTimeInterval(3_600)
        )))
        try context.save()

        let count = try await LocalActionCenterDataStore(modelContainer: container)
            .totalCount(
                dismissedSuggestionFingerprints: [],
                payday: 1,
                weekendMultiplier: 1
            )

        XCTAssertEqual(count, 1)
    }
}
