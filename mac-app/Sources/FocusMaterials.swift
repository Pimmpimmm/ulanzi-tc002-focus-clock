import AppKit
import QuartzCore

/// All three pages share the full-bleed material, including the content behind navigation.
final class WoodBackgroundView: NSView {
    private let texture = Bundle.main.url(forResource: "OakTexture", withExtension: "png").flatMap(NSImage.init(contentsOf:))
    override var isOpaque: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        FocusPalette.background.setFill(); bounds.fill()
        if let texture, texture.size.width > 0, texture.size.height > 0 {
            let scale = max(bounds.width / texture.size.width, bounds.height / texture.size.height)
            let size = NSSize(width: texture.size.width * scale, height: texture.size.height * scale)
            let frame = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
            texture.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
        }
        // Preserve the grain, while maintaining contrast in both appearances.
        (dark ? NSColor(srgbRed: 0.07, green: 0.06, blue: 0.05, alpha: 0.80) : NSColor.white.withAlphaComponent(0.22)).setFill()
        bounds.fill()
    }
}

/// Uses Apple's actual Liquid Glass on macOS 26+, without raising the app's macOS 13 minimum.
final class FloatingNavigationView: NSView {
    private var compatibilityMaterial: NSVisualEffectView?
    private let buttons: [ConsoleButton]
    private let row: NSStackView
    private let selection = NavigationSelectionHighlight(frame: .zero)
    private weak var selectionHost: NSView?
    private var selectedIndex = 0
    private var dragStart: NSPoint?
    private var isDragging = false
    private var animationGeneration = 0
    private var isAnimating = false
    private var windowObserver: NSObjectProtocol?
    var onSelection: ((Int) -> Void)?

    init(content: NSStackView, buttons: [ConsoleButton], forceCompatibility: Bool) {
        self.buttons = buttons; self.row = content
        super.init(frame: .zero)
        for button in buttons {
            button.onNavigationPointer = { [weak self] event, phase in self?.handlePointer(event, phase: phase) }
            button.onNavigationKey = { [weak self] event in self?.handleKey(event) ?? false }
            button.toolTip = "点击或横向拖动切换页面；方向键也可以切换。"
        }
        #if TC002_NATIVE_GLASS
        if #available(macOS 26.0, *), !forceCompatibility {
            let glass = NSGlassEffectView()
            glass.style = .regular; glass.cornerRadius = 32
            #if TC002_GLASS_INTERACTION
            if #available(macOS 27.0, *) { glass.effectIsInteractive = true }
            #endif
            let container = NSView()
            glass.contentView = container
            addSurface(glass)
            addContent(content, to: container)
            return
        }
        #endif
        let material = NSVisualEffectView()
        material.material = .popover; material.blendingMode = .withinWindow; material.state = .active
        material.wantsLayer = true; material.layer?.cornerRadius = 32; material.layer?.masksToBounds = true
        let mask = NSImage(size: NSSize(width: 348, height: 64), flipped: false) { rect in
            NSColor.black.setFill(); NSBezierPath(roundedRect: rect, xRadius: 32, yRadius: 32).fill(); return true
        }
        material.maskImage = mask
        compatibilityMaterial = material
        addSurface(material); addContent(content, to: material)
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) } }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver); self.windowObserver = nil }
        if let window {
            windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                guard let self, self.dragStart != nil else { return }
                self.dragStart = nil; self.isDragging = false
                self.buttons.forEach { $0.isHighlighted = false }
                self.select(index: self.selectedIndex)
            }
        }
    }

    private func addSurface(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func addContent(_ view: NSView, to parent: NSView) {
        selectionHost = parent; parent.addSubview(selection)
        view.translatesAutoresizingMaskIntoConstraints = false; parent.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: 10),
            view.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -10),
            view.centerYAnchor.constraint(equalTo: parent.centerYAnchor)
        ])
    }

    func refreshAppearance() {
        compatibilityMaterial?.layer?.borderWidth = 1
        compatibilityMaterial?.layer?.borderColor = FocusPalette.surface.withAlphaComponent(0.7).cgColor
        selection.needsDisplay = true
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshAppearance() }

    override func layout() {
        super.layout()
        subviews.first?.layoutSubtreeIfNeeded()
        if dragStart == nil && !isAnimating { selection.frame = selectionRect(at: selectedIndex) }
    }

    private func selectionRect(at index: Int) -> NSRect {
        guard let host = selectionHost, buttons.indices.contains(index) else { return .zero }
        return buttons[index].convert(buttons[index].bounds, to: host).insetBy(dx: -1, dy: -1)
    }

    func select(index: Int, animated: Bool = true) {
        guard buttons.indices.contains(index) else { return }
        selectedIndex = index; animationGeneration += 1
        let generation = animationGeneration
        let target = selectionRect(at: index)
        guard target.width > 0 else { needsLayout = true; return }
        if !animated || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            isAnimating = false; selection.frame = target; return
        }
        isAnimating = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.95, 0.32, 1)
            selection.animator().frame = target
        }, completionHandler: { [weak self] in
            guard let self, self.animationGeneration == generation else { return }
            self.isAnimating = false; self.needsLayout = true
        })
    }

    private func index(at x: CGFloat) -> Int {
        NavigationPosition.index(at: Double(x), firstCenter: Double(selectionRect(at: 0).midX), lastCenter: Double(selectionRect(at: buttons.count - 1).midX), count: buttons.count)
    }

    private func handlePointer(_ event: NSEvent, phase: NavigationPointerPhase) {
        guard let host = selectionHost else { return }
        let point = host.convert(event.locationInWindow, from: nil)
        switch phase {
        case .began:
            animationGeneration += 1; isAnimating = false
            // Freeze at the presentation frame if a new gesture interrupts a slide.
            if let frame = selection.layer?.presentation()?.frame { selection.frame = frame }
            selection.layer?.removeAllAnimations()
            dragStart = point; isDragging = false
        case .moved:
            guard let start = dragStart else { return }
            guard abs(point.x - start.x) > 4 || isDragging else { return }
            isDragging = true
            let first = selectionRect(at: 0); let last = selectionRect(at: buttons.count - 1)
            let center = min(last.midX, max(first.midX, point.x))
            let stretch: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 6
            selection.frame = NSRect(x: center - (first.width + stretch) / 2, y: first.minY - (stretch > 0 ? 1 : 0), width: first.width + stretch, height: first.height + (stretch > 0 ? 2 : 0))
        case .ended:
            guard dragStart != nil else { return }
            let inside = point.y >= host.bounds.minY - 20 && point.y <= host.bounds.maxY + 20
            let target = isDragging ? index(at: selection.frame.midX) : index(at: point.x)
            dragStart = nil; isDragging = false
            if inside { onSelection?(target) } else { select(index: selectedIndex) }
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            dragStart = nil; isDragging = false; select(index: selectedIndex); return true
        }
        guard event.keyCode == 123 || event.keyCode == 124 else { return false }
        let next = min(buttons.count - 1, max(0, selectedIndex + (event.keyCode == 124 ? 1 : -1)))
        onSelection?(next); window?.makeFirstResponder(buttons[next]); return true
    }
}

private final class NavigationSelectionHighlight: NSView {
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; setAccessibilityElement(false) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            FocusPalette.surface.setFill(); path.fill()
        } else {
            NSGradient(starting: NSColor.white.withAlphaComponent(dark ? 0.27 : 0.60), ending: NSColor.white.withAlphaComponent(dark ? 0.06 : 0.12))?.draw(in: path, angle: -90)
        }
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            NSColor.labelColor.setStroke()
        } else { NSColor.white.withAlphaComponent(dark ? 0.35 : 0.75).setStroke() }
        path.lineWidth = 1; path.stroke()
    }
}
