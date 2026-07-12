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

    func testLabelFramesStayInsideWheelRimAcrossSupportedCounts() {
        for count in 3...9 {
            let preferredSize = CategoryWheelLayout.preferredSize(
                itemCount: count,
                availableWidth: 400,
                availableHeight: 700
            )

            for size in [preferredSize, 250] {
                let layout = CategoryWheelLayout(itemCount: count, size: size)

                for index in 0..<count {
                    let frame = layout.labelFrame(for: index)
                    let corners = [
                        CGPoint(x: frame.minX, y: frame.minY),
                        CGPoint(x: frame.maxX, y: frame.minY),
                        CGPoint(x: frame.minX, y: frame.maxY),
                        CGPoint(x: frame.maxX, y: frame.maxY),
                    ]

                    for corner in corners {
                        let distance = hypot(corner.x - layout.center.x, corner.y - layout.center.y)
                        XCTAssertLessThanOrEqual(
                            distance,
                            layout.outerRadius - 1,
                            "Expected label \(index) to remain inside a \(count)-item wheel at size \(size)"
                        )
                    }
                }
            }
        }
    }

    func testDialStateReportsEntryMoveAndExitWithoutRetainingStaleSector() {
        let layout = CategoryWheelLayout(itemCount: 6, size: 326)
        var state = CategoryWheelDialState()
        let first = layout.labelPoint(for: 1)
        let second = layout.labelPoint(for: 2)

        XCTAssertEqual(state.update(location: first, layout: layout), .entered(1))
        XCTAssertEqual(state.activeIndex, 1)
        XCTAssertEqual(state.update(location: first, layout: layout), .unchanged)
        XCTAssertEqual(state.update(location: second, layout: layout), .moved(from: 1, to: 2))
        XCTAssertEqual(state.update(location: layout.center, layout: layout), .exited(2))
        XCTAssertNil(state.activeIndex)
    }

    func testDialStateResetClearsAStaleSelectionBeforeRelease() {
        let layout = CategoryWheelLayout(itemCount: 6, size: 326)
        var state = CategoryWheelDialState()

        XCTAssertEqual(state.update(location: layout.labelPoint(for: 4), layout: layout), .entered(4))
        XCTAssertNil(layout.index(at: layout.center))
        state.reset()
        XCTAssertNil(state.activeIndex)
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
