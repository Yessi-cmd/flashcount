import SwiftUI

/// Shared geometry for wheel drawing and hit testing.
struct CategoryWheelLayout: Equatable {
    let itemCount: Int
    let size: CGFloat

    init(itemCount: Int, size: CGFloat) {
        self.itemCount = max(itemCount, 1)
        self.size = size
    }

    static func preferredSize(itemCount: Int, availableWidth: CGFloat, availableHeight: CGFloat) -> CGFloat {
        let ideal: CGFloat = itemCount <= 5 ? 304 : itemCount <= 7 ? 326 : 348
        return max(250, min(ideal, availableWidth, availableHeight))
    }

    var center: CGPoint { CGPoint(x: size / 2, y: size / 2) }
    var outerRadius: CGFloat { size * 0.488 }
    var innerRadius: CGFloat { itemCount <= 5 ? size * 0.235 : itemCount <= 7 ? size * 0.215 : size * 0.198 }
    var labelRadius: CGFloat { (innerRadius + outerRadius) * 0.515 }
    var sectorAngle: Double { 360 / Double(itemCount) }
    var sectorInset: Double { itemCount <= 5 ? 1.8 : itemCount <= 7 ? 1.35 : 1 }

    func middleAngle(for index: Int) -> Double { -90 + Double(index) * sectorAngle }

    func labelPoint(for index: Int, radialOffset: CGFloat = 0) -> CGPoint {
        let angle = Angle.degrees(middleAngle(for: index)).radians
        let radius = labelRadius + radialOffset
        return CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
    }

    func sectorPath(for index: Int, radialOffset: CGFloat = 0) -> Path {
        let middle = middleAngle(for: index)
        let angle = Angle.degrees(middle).radians
        let shiftedCenter = CGPoint(
            x: center.x + CGFloat(cos(angle)) * radialOffset,
            y: center.y + CGFloat(sin(angle)) * radialOffset
        )
        let start = Angle.degrees(middle - sectorAngle / 2 + sectorInset)
        let end = Angle.degrees(middle + sectorAngle / 2 - sectorInset)
        var path = Path()
        path.addArc(center: shiftedCenter, radius: outerRadius, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: shiftedCenter, radius: innerRadius, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }

    func index(at location: CGPoint) -> Int? {
        let deltaX = location.x - center.x
        let deltaY = location.y - center.y
        let radius = hypot(deltaX, deltaY)
        guard radius >= innerRadius, radius <= outerRadius else { return nil }
        let angle = atan2(deltaY, deltaX) * 180 / .pi
        let normalized = (angle + 90 + 360).truncatingRemainder(dividingBy: 360)
        return Int((normalized + sectorAngle / 2) / sectorAngle) % itemCount
    }
}
