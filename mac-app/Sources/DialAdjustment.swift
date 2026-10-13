import Foundation

struct DialAdjustment {
    private var previousAngle: Double?
    private var remainder = 0.0

    mutating func begin(at angle: Double) {
        previousAngle = angle
        remainder = 0
    }

    // Relative rotation: pressing any point on the ring keeps the current value.
    // One revolution is 60 minutes; crossing the angle seam never resets it.
    mutating func move(to angle: Double, current: Int) -> Int {
        guard let previousAngle else { begin(at: angle); return current }
        var delta = angle - previousAngle
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        self.previousAngle = angle
        remainder += delta / (.pi / 30)
        let steps = Int(floor(abs(remainder) + 1e-9)) * (remainder < 0 ? -1 : 1)
        remainder -= Double(steps)
        if abs(remainder) < 1e-9 { remainder = 0 }
        let value = min(240, max(1, current + steps))
        if current + steps != value { remainder = 0 }
        return value
    }
}
