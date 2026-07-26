import XCTest
import SwiftUI
@testable import FlashCount

/// 分享卡片必须在脱离视图层级时也能渲染出实际内容——
/// `ImageRenderer` 拿不到环境对象，任何隐式依赖都会渲染成空白。
@MainActor
final class ReportShareCardTests: XCTestCase {
    func testShareCardRendersNonBlankImage() throws {
        let card = ReportShareCard(
            periodTitle: "周报",
            rangeTitle: "2026年7月20日–2026年7月26日",
            totalExpense: Decimal(string: "220.90")!,
            income: (total: 8_000, net: Decimal(string: "7779.10")!),
            topCategories: [
                CategorySpending(
                    categoryName: "餐饮",
                    categoryIcon: "fork.knife",
                    categoryColor: "#FF6B6B",
                    amount: Decimal(string: "180.90")!,
                    percentage: 0.82,
                    changeFromLastPeriod: 0.35
                ),
                CategorySpending(
                    categoryName: "出行",
                    categoryIcon: "car.fill",
                    categoryColor: "#4EA8F8",
                    amount: 40,
                    percentage: 0.18,
                    changeFromLastPeriod: nil
                )
            ],
            streakDays: 12
        )
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage, "分享卡片必须渲染成功")

        XCTAssertEqual(image.size.width, ReportShareCard.width + 24, accuracy: 1, "宽度应为卡片宽度加外边距")
        XCTAssertGreaterThan(image.size.height, 200, "卡片应有实际高度而非塌缩")

        let attachment = XCTAttachment(image: image)
        attachment.name = "report-share-card"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertFalse(try isBlank(image), "渲染结果不得为纯色空白")
    }

    /// 采样若干像素，确认画面中确实存在深浅差异（文字/色块）。
    private func isBlank(_ image: UIImage) throws -> Bool {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minimum: UInt8 = 255
        var maximum: UInt8 = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let luminance = pixels[index]
            minimum = min(minimum, luminance)
            maximum = max(maximum, luminance)
        }
        return Int(maximum) - Int(minimum) < 32
    }
}
