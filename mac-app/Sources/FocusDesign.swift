import AppKit

enum FocusPalette {
    private static func color(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        }
    }
    static let background = color(0xF5F4F0, 0x171B21)
    static let surface = color(0xFFFFFF, 0x20262E)
    static let settingsSurface = color(0xFCF9F1, 0x2D241C)
    static let settingsBorder = color(0xCABBA6, 0x6B5843)
    static let inset = color(0xF3F3F0, 0x191F26)
    static let rail = color(0xECECE6, 0x1C2229)
    static let text = NSColor.labelColor
    // Opaque warm secondary ink stays readable on the shared wood in both appearances.
    static let muted = color(0x594635, 0xDCC8AD)
    static let faint = muted
    static let border = color(0xE3E5DF, 0x343C45)
    static let accent = color(0xB95739, 0xF0A180)
    static let accentSoft = color(0xF5E6DD, 0x3E302C)
    static let ready = color(0x33786B, 0x86BBA5)
    static let readySoft = color(0xE8F0E9, 0x263B34)
    static let warning = color(0xA8752B, 0xDAB16D)
    static let clockInk = color(0x332317, 0xFFECD1)
    static let clockBronze = color(0x873D24, 0xFBC18C)
    static let clockRest = color(0x24543D, 0xACD9B5)
    static let clockTick = color(0x7D5B40, 0xC4AD8E)
}

enum NavigationPointerPhase { case began, moved, ended }

final class ConsoleButton: NSButton {
    enum Style { case primary, secondary, quiet, tab, selectedTab }
    var style: Style = .secondary { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat? { didSet { needsDisplay = true } }
    var isNavigationItem = false {
        didSet { focusRingType = isNavigationItem ? .none : .default; needsDisplay = true }
    }
    /// Home controls use warm ink against wood, rather than gray intended for plain forms.
    var foregroundColor: NSColor? { didSet { needsDisplay = true } }
    var onNavigationPointer: ((NSEvent, NavigationPointerPhase) -> Void)?
    var onNavigationKey: ((NSEvent) -> Bool)?
    private var isHovered = false
    private var navigationKeyboardFocus = false
    private var hoverTracking: NSTrackingArea?
    override var isOpaque: Bool { false }
    override var allowsVibrancy: Bool { false }

    override var intrinsicContentSize: NSSize {
        let size = (title as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 12, weight: .medium)])
        return NSSize(width: ceil(size.width) + (image == nil ? 28 : 50), height: style == .primary ? 44 : 34)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverTracking = area
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            navigationKeyboardFocus = isNavigationItem && NSApp.currentEvent?.type == .keyDown
            needsDisplay = true
        }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { navigationKeyboardFocus = false; needsDisplay = true }
        return accepted
    }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let onNavigationPointer else { super.mouseDown(with: event); return }
        navigationKeyboardFocus = false
        window?.makeFirstResponder(self); isHighlighted = true; onNavigationPointer(event, .began)
    }
    override func mouseDragged(with event: NSEvent) {
        if let onNavigationPointer {
            isHighlighted = bounds.contains(convert(event.locationInWindow, from: nil))
            onNavigationPointer(event, .moved)
        } else { super.mouseDragged(with: event) }
    }
    override func mouseUp(with event: NSEvent) {
        if let onNavigationPointer { isHighlighted = false; onNavigationPointer(event, .ended) } else { super.mouseUp(with: event) }
    }
    override func keyDown(with event: NSEvent) {
        if isNavigationItem { navigationKeyboardFocus = true; needsDisplay = true }
        if onNavigationKey?(event) != true { super.keyDown(with: event) }
    }
    override func draw(_ dirtyRect: NSRect) {
        let fill: NSColor
        var foreground: NSColor
        switch style {
        case .primary: fill = FocusPalette.accent; foreground = FocusPalette.background
        case .selectedTab:
            fill = isNavigationItem ? .clear : FocusPalette.surface
            foreground = FocusPalette.text
        case .secondary: fill = FocusPalette.inset; foreground = FocusPalette.text
        case .quiet, .tab: fill = .clear; foreground = FocusPalette.muted
        }
        foreground = foregroundColor ?? foreground
        let opacity: CGFloat = isEnabled ? 1 : 0.45
        let radius = cornerRadius ?? (style == .primary ? 12 : 9)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        fill.withAlphaComponent(fill.alphaComponent * opacity).setFill(); path.fill()
        if style == .secondary || (style == .selectedTab && !isNavigationItem) {
            FocusPalette.border.withAlphaComponent(opacity).setStroke(); path.lineWidth = 1; path.stroke()
        }
        if isEnabled && (isHovered || isHighlighted) {
            foreground.withAlphaComponent(isHighlighted ? 0.11 : 0.055).setFill(); path.fill()
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: foreground.withAlphaComponent(opacity)]
        let titleSize = (title as NSString).size(withAttributes: attributes)
        let iconWidth: CGFloat = image == nil ? 0 : (title.isEmpty ? 14 : 21)
        let originX = (bounds.width - titleSize.width - iconWidth) / 2
        if let image {
            let icon = image.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [foreground.withAlphaComponent(opacity)])) ?? image
            icon.draw(in: NSRect(x: originX, y: (bounds.height - 14) / 2, width: 14, height: 14), from: .zero, operation: .sourceOver, fraction: opacity, respectFlipped: true, hints: nil)
        }
        (title as NSString).draw(at: NSPoint(x: originX + iconWidth, y: (bounds.height - titleSize.height) / 2), withAttributes: attributes)
        if window?.firstResponder === self {
            if !isNavigationItem {
                NSFocusRingPlacement.only.set(); path.fill()
            } else if navigationKeyboardFocus && window?.isKeyWindow == true {
                // Keep keyboard orientation without the blue system outline over Liquid Glass.
                FocusPalette.clockBronze.setFill()
                NSBezierPath(roundedRect: NSRect(x: bounds.midX - 12, y: 5, width: 24, height: 2), xRadius: 1, yRadius: 1).fill()
            }
        }
    }
}

private func paddedRect(_ bounds: NSRect, font: NSFont?) -> NSRect {
    let height = ceil((font?.ascender ?? 12) - (font?.descender ?? -3) + 3)
    return NSRect(x: bounds.minX + 12, y: bounds.minY + (bounds.height - height) / 2, width: max(0, bounds.width - 24), height: height)
}

final class ConsoleTextCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect { paddedRect(rect, font: font) }
    override func select(withFrame rect: NSRect, in controlView: NSView, editor: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: editor, delegate: delegate, start: selStart, length: selLength)
    }
    override func edit(withFrame rect: NSRect, in controlView: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: editor, delegate: delegate, event: event)
    }
}

final class ConsoleSecureCell: NSSecureTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect { paddedRect(rect, font: font) }
    override func select(withFrame rect: NSRect, in controlView: NSView, editor: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: editor, delegate: delegate, start: selStart, length: selLength)
    }
    override func edit(withFrame rect: NSRect, in controlView: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: editor, delegate: delegate, event: event)
    }
}

final class FocusDialView: NSView {
    enum Mode { case focus, rest }
    var mode: Mode = .focus { didSet { needsDisplay = true; updateAccessibility() } }
    var focusMinutes = 45 { didSet { needsDisplay = true } }
    var restMinutes = 5 { didSet { needsDisplay = true } }
    var isEnabled = true { didSet { needsDisplay = true; updateAccessibility(); window?.invalidateCursorRects(for: self) } }
    var onMinutesChanged: ((Int) -> Void)?
    var onEditingEnded: (() -> Void)?
    private var rotation = DialAdjustment()
    private var dragging = false
    private var scrollRemainder = 0.0
    private var dialCenter: NSPoint { NSPoint(x: bounds.midX, y: bounds.midY + 3) }
    private var dialRadius: CGFloat { min(bounds.width, bounds.height) / 2 - 21 }
    private var minutes: Int { mode == .focus ? focusMinutes : restMinutes }
    override var acceptsFirstResponder: Bool { isEnabled }

    func updateAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel(mode == .focus ? "专注时长旋钮" : "休息时长旋钮")
        setAccessibilityValue(minutes)
        setAccessibilityValueDescription("\(minutes) 分钟")
        setAccessibilityMinValue(1); setAccessibilityMaxValue(240)
        setAccessibilityEnabled(isEnabled)
        setAccessibilityHelp("拖动圆环，顺时针增加，逆时针减少；也可以用方向键，每次调整一分钟。下次启动时生效。")
    }
    override func resetCursorRects() {
        guard isEnabled else { return }
        let circle = NSRect(x: dialCenter.x - dialRadius - 12, y: dialCenter.y - dialRadius - 12, width: 2 * dialRadius + 24, height: 2 * dialRadius + 24)
        let band: CGFloat = 36
        for rect in [NSRect(x: circle.minX, y: circle.minY, width: circle.width, height: band),
                     NSRect(x: circle.minX, y: circle.maxY - band, width: circle.width, height: band),
                     NSRect(x: circle.minX, y: circle.minY + band, width: band, height: circle.height - 2 * band),
                     NSRect(x: circle.maxX - band, y: circle.minY + band, width: band, height: circle.height - 2 * band)] {
            addCursorRect(rect, cursor: .openHand)
        }
    }
    private func angle(at point: NSPoint) -> Double { atan2(Double(point.x - dialCenter.x), Double(point.y - dialCenter.y)) }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)
        let distance = hypot(point.x - dialCenter.x, point.y - dialCenter.y)
        guard distance >= dialRadius - 28, distance <= dialRadius + 18 else { return }
        window?.makeFirstResponder(self)
        rotation.begin(at: angle(at: point)); dragging = true
        NSCursor.closedHand.push(); needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard isEnabled && dragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - dialCenter.x, point.y - dialCenter.y) >= dialRadius * 0.45 else { return }
        setMinutes(rotation.move(to: angle(at: point), current: minutes))
    }
    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false; NSCursor.pop(); needsDisplay = true
        onEditingEnded?()
    }
    override func scrollWheel(with event: NSEvent) {
        guard isEnabled, event.momentumPhase.isEmpty else { return }
        scrollRemainder += Double(event.scrollingDeltaY) / (event.hasPreciseScrollingDeltas ? 12 : 1)
        let steps = Int(scrollRemainder)
        if steps != 0 {
            scrollRemainder -= Double(steps); setMinutes(minutes + steps)
            if event.phase.isEmpty { onEditingEnded?() }
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) { scrollRemainder = 0; onEditingEnded?() }
    }
    override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        let step = event.modifierFlags.contains(.shift) ? 5 : 1
        switch event.keyCode {
        case 123, 125: setMinutes(minutes - step)
        case 124, 126: setMinutes(minutes + step)
        default: super.keyDown(with: event); return
        }
        onEditingEnded?()
    }
    override func accessibilityPerformIncrement() -> Bool {
        guard isEnabled, minutes < 240 else { return false }; setMinutes(minutes + 1); onEditingEnded?(); return true
    }
    override func accessibilityPerformDecrement() -> Bool {
        guard isEnabled, minutes > 1 else { return false }; setMinutes(minutes - 1); onEditingEnded?(); return true
    }
    private func setMinutes(_ value: Int) {
        let value = min(240, max(1, value))
        guard value != minutes else { return }
        if mode == .focus { focusMinutes = value } else { restMinutes = value }
        updateAccessibility(); onMinutesChanged?(value)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let center = dialCenter
        let radius = dialRadius
        let scale = min(bounds.width, bounds.height) / 220
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let accent = (mode == .focus ? FocusPalette.clockBronze : FocusPalette.clockRest).withAlphaComponent(isEnabled ? 1 : 0.55)
        let caseRect = NSRect(x: center.x - radius + 17, y: center.y - radius + 17, width: (radius - 17) * 2, height: (radius - 17) * 2)
        let casePath = NSBezierPath(ovalIn: caseRect)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.4 : 0.22)
        shadow.shadowBlurRadius = 10; shadow.shadowOffset = NSSize(width: 0, height: -4); shadow.set()
        (dark ? NSColor(srgbRed: 0.31, green: 0.24, blue: 0.17, alpha: 1) : NSColor(srgbRed: 0.88, green: 0.76, blue: 0.59, alpha: 1)).setFill(); casePath.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: NSColor.white.withAlphaComponent(dark ? 0.16 : 0.65), ending: NSColor.black.withAlphaComponent(0.20))?.draw(in: casePath, angle: -65)
        let face = NSBezierPath(ovalIn: caseRect.insetBy(dx: 6, dy: 6))
        let faceTop = dark ? NSColor(srgbRed: 0.19, green: 0.14, blue: 0.10, alpha: 1) : NSColor(srgbRed: 1, green: 0.97, blue: 0.88, alpha: 1)
        let faceBottom = dark ? NSColor(srgbRed: 0.12, green: 0.09, blue: 0.07, alpha: 1) : NSColor(srgbRed: 0.94, green: 0.88, blue: 0.74, alpha: 1)
        NSGradient(starting: faceTop, ending: faceBottom)?.draw(in: face, angle: -65)
        NSColor.black.withAlphaComponent(0.22).setStroke(); face.lineWidth = 1; face.stroke()
        let activeTicks = (minutes - 1) % 60 + 1
        for index in 0..<60 {
            let angle = CGFloat(Double.pi / 2 - Double(index) * Double.pi / 30)
            let inner = radius - (index % 5 == 0 ? 10 : 6) * scale
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            tick.line(to: NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
            tick.lineWidth = 2.5 * sqrt(scale); tick.lineCapStyle = .round
            (index < activeTicks ? accent : FocusPalette.clockTick.withAlphaComponent(isEnabled ? 0.75 : 0.35)).setStroke()
            tick.stroke()
        }
        let knobAngle = CGFloat(.pi / 2 - Double(minutes % 60) * .pi / 30)
        let knob = NSPoint(x: center.x + cos(knobAngle) * (radius + 6), y: center.y + sin(knobAngle) * (radius + 6))
        accent.setFill()
        NSBezierPath(ovalIn: NSRect(x: knob.x - 4, y: knob.y - 4, width: 8, height: 8)).fill()
        let innerRing = NSBezierPath(ovalIn: NSRect(x: center.x - radius + 20, y: center.y - radius + 20, width: (radius - 20) * 2, height: (radius - 20) * 2))
        NSColor.white.withAlphaComponent(dark ? 0.15 : 0.65).setStroke(); innerRing.lineWidth = 1; innerRing.stroke()
        drawCentered(mode == .focus ? "FOCUS" : "REST", y: center.y + 29 * scale, font: .monospacedSystemFont(ofSize: 10 * scale, weight: .semibold), color: accent)
        drawCentered(String(format: "%02d:00", minutes), y: center.y - 14 * scale, font: .monospacedDigitSystemFont(ofSize: (minutes >= 100 ? 33 : 39) * scale, weight: .medium), color: FocusPalette.clockInk)
        drawCentered("拖动圆环调节", y: center.y - 37 * scale, font: .systemFont(ofSize: 10, weight: .medium), color: FocusPalette.clockTick)
        if window?.firstResponder === self {
            accent.withAlphaComponent(0.3).setStroke(); innerRing.lineWidth = 1.5; innerRing.stroke()
        }
    }
    private func drawCentered(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2, y: y), withAttributes: attributes)
    }
}

final class RhythmStripView: NSView {
    var focusMinutes = 45 { didSet { refreshDescription() } }
    var restMinutes = 5 { didSet { refreshDescription() } }
    private func refreshDescription() {
        needsDisplay = true
        setAccessibilityElement(true); setAccessibilityRole(.image)
        setAccessibilityLabel("专注节奏：专注 \(focusMinutes) 分钟，休息 \(restMinutes) 分钟。")
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 3, bounds.height > 0 else { return }
        // Continuous proportions keep short breaks visible, unlike rounding to 24 blocks.
        let focus = CGFloat(max(1, focusMinutes)); let rest = CGFloat(max(1, restMinutes))
        let width = (bounds.width - 3) * focus / (focus + rest)
        let focusRect = NSRect(x: bounds.minX, y: bounds.minY, width: width, height: bounds.height)
        let restRect = NSRect(x: focusRect.maxX + 3, y: bounds.minY, width: bounds.width - width - 3, height: bounds.height)
        FocusPalette.clockBronze.setFill()
        NSBezierPath(roundedRect: focusRect, xRadius: 2, yRadius: 2).fill()
        FocusPalette.clockRest.setFill()
        NSBezierPath(roundedRect: restRect, xRadius: 2, yRadius: 2).fill()
    }
}

/// Customize only native scroller parts, keeping AppKit's hit testing, dragging and fade behavior.
final class KnobOnlyScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override var isOpaque: Bool { false }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // No track fill or border: the shared wood remains visible beneath the thumb.
    }
    override func drawKnob() {
        guard isEnabled else { return }
        let nativeRect = rect(for: .knob)
        guard nativeRect.width > 0, nativeRect.height > 0 else { return }
        let width = min(6, nativeRect.width)
        let thumb = NSRect(x: nativeRect.midX - width / 2, y: nativeRect.minY, width: width, height: nativeRect.height)
        let opacity: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1 : 0.75
        FocusPalette.clockTick.withAlphaComponent(opacity).setFill()
        NSBezierPath(roundedRect: thumb, xRadius: width / 2, yRadius: width / 2).fill()
    }
}

final class FlippedContentView: NSView { override var isFlipped: Bool { true } }
