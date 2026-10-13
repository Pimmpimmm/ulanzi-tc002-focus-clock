import Foundation

@main
enum DialAdjustmentTests {
    static func main() {
        let step = Double.pi / 30
        var dial = DialAdjustment()
        dial.begin(at: 1.2)
        precondition(dial.move(to: 1.2, current: 30) == 30, "pressing the ring must not jump")
        precondition(dial.move(to: 1.2 + step, current: 30) == 31, "clockwise increases from the current value")
        precondition(dial.move(to: 1.2, current: 31) == 30, "counterclockwise reverses the adjustment")

        dial.begin(at: .pi - step / 2)
        precondition(dial.move(to: -.pi + step / 2, current: 30) == 31, "crossing the seam clockwise adds one")
        precondition(dial.move(to: .pi - step / 2, current: 31) == 30, "crossing the seam backwards subtracts one")

        dial.begin(at: 0)
        var value = 30
        for index in 1...3 { value = dial.move(to: Double(index) * step / 3, current: value) }
        precondition(value == 31, "small drag movements must accumulate")

        dial.begin(at: 0)
        value = 30
        for index in 1...90 {
            let angle = Double(index) * step
            value = dial.move(to: atan2(sin(angle), cos(angle)), current: value)
        }
        precondition(value == 120, "multiple turns retain the accumulated minutes")

        dial.begin(at: 0)
        precondition(dial.move(to: step * 10, current: 238) == 240, "upper bound is 240")
        precondition(dial.move(to: step * 9, current: 240) == 239, "reversing at the upper bound responds immediately")
        dial.begin(at: 0)
        precondition(dial.move(to: -step * 10, current: 3) == 1, "lower bound is 1")
        precondition(dial.move(to: -step * 9, current: 1) == 2, "reversing at the lower bound responds immediately")

        dial.begin(at: 2)
        precondition(dial.move(to: 2 + step, current: 5) == 6, "a new gesture uses the selected mode's current value")
        print("旋钮验收通过：相对旋转、角度跨界、细小移动、多圈、上下限和重新拖动。")
        for (x, expected) in [(-100.0, 0), (50, 0), (99, 0), (101, 1), (150, 1), (199, 1), (201, 2), (250, 2), (900, 2)] {
            precondition(NavigationPosition.index(at: x, firstCenter: 50, lastCenter: 250, count: 3) == expected, "navigation drag snaps to the closest valid page")
        }
        precondition(NavigationPosition.index(at: .nan, firstCenter: 50, lastCenter: 250, count: 3) == 0)
        precondition(NavigationPosition.index(at: 50, firstCenter: 50, lastCenter: 50, count: 1) == 0)
        print("导航验收通过：三页吸附、边界钳制和无效坐标。")
    }
}
