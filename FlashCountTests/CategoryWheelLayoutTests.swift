import CoreGraphics
import XCTest
@testable import FlashCount

final class CategoryWheelLayoutTests: XCTestCase {
    func testCategoryCentersMapToTheirOwnSectorAcrossSupportedCounts() {
        for count in [3, 5, 6, 9] {
            let layout = CategoryWheelLayout(itemCount: count, size: 320)

            for index in 0..<count {
                XCTAssertEqual(
                    layout.index(at: layout.labelPoint(for: index)),
                    index,
                    "Expected item \(index) to be selectable in a \(count)-item wheel"
                )
            }
        }
    }

    func testPointsInsideHubAndOutsideRimAreNotSelectable() {
        let layout = CategoryWheelLayout(itemCount: 9, size: 348)
        let insideHub = CGPoint(x: layout.center.x, y: layout.center.y - layout.innerRadius + 1)
        let outsideRim = CGPoint(x: layout.center.x, y: layout.center.y - layout.outerRadius - 1)

        XCTAssertNil(layout.index(at: insideHub))
        XCTAssertNil(layout.index(at: outsideRim))
    }

    func testClockwiseBoundaryMovesToNextSector() {
        let layout = CategoryWheelLayout(itemCount: 6, size: 326)
        let boundary = layout.middleAngle(for: 2) + layout.sectorAngle / 2
        let beforeBoundary = point(in: layout, angle: boundary - 0.01)
        let afterBoundary = point(in: layout, angle: boundary + 0.01)

        XCTAssertEqual(layout.index(at: beforeBoundary), 2)
        XCTAssertEqual(layout.index(at: afterBoundary), 3)
    }

    func testTopSectorWrapsBetweenLastAndFirstItem() {
        let layout = CategoryWheelLayout(itemCount: 9, size: 348)
        let counterClockwiseBoundary = layout.middleAngle(for: 0) - layout.sectorAngle / 2
        let insideFirst = point(in: layout, angle: counterClockwiseBoundary + 0.01)
        let insideLast = point(in: layout, angle: counterClockwiseBoundary - 0.01)

        XCTAssertEqual(layout.index(at: insideFirst), 0)
        XCTAssertEqual(layout.index(at: insideLast), 8)
    }

    func testPreferredSizeAdaptsToDensityAndAvailableSpace() {
        XCTAssertEqual(CategoryWheelLayout.preferredSize(itemCount: 3, availableWidth: 400, availableHeight: 700), 304)
        XCTAssertEqual(CategoryWheelLayout.preferredSize(itemCount: 6, availableWidth: 400, availableHeight: 700), 326)
        XCTAssertEqual(CategoryWheelLayout.preferredSize(itemCount: 9, availableWidth: 400, availableHeight: 700), 348)
        XCTAssertEqual(CategoryWheelLayout.preferredSize(itemCount: 9, availableWidth: 290, availableHeight: 700), 290)
    }

    private func point(in layout: CategoryWheelLayout, angle: Double) -> CGPoint {
        let radians = angle * .pi / 180
        let radius = (layout.innerRadius + layout.outerRadius) / 2
        return CGPoint(
            x: layout.center.x + CGFloat(cos(radians)) * radius,
            y: layout.center.y + CGFloat(sin(radians)) * radius
        )
    }
}
