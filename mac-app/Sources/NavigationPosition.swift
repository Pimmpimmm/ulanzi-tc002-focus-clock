import Foundation

enum NavigationPosition {
    static func index(at x: Double, firstCenter: Double, lastCenter: Double, count: Int) -> Int {
        guard count > 1, x.isFinite, firstCenter.isFinite, lastCenter.isFinite, lastCenter > firstCenter else { return 0 }
        let progress = min(1, max(0, (x - firstCenter) / (lastCenter - firstCenter)))
        return Int((progress * Double(count - 1)).rounded())
    }
}
