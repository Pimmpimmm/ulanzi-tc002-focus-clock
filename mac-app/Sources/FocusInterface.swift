import AppKit
import UniformTypeIdentifiers

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    private let model = AppModel()
    private var window: NSWindow!
    private let deviceField = NSTextField()
    private let hostField = NSTextField()
    private let focusField = NSTextField()
    private let restField = NSTextField()
    private let appIDField = NSTextField()
    private let appSecretField = NSSecureTextField()
    private let repoField = NSTextField()
    private let statusField = NSTextField(labelWithString: "")
    private let logView = NSTextView()
    private let startButton = ConsoleButton(title: "启动专注时钟", target: nil, action: nil)
    private let stopButton = ConsoleButton(title: "停止助手", target: nil, action: nil)
    private let rebootButton = ConsoleButton(title: "恢复原生界面", target: nil, action: nil)
    private let authorizeButton = ConsoleButton(title: "授权 Lark", target: nil, action: nil)
    private let environmentButton = ConsoleButton(title: "检查环境", target: nil, action: nil)
    private let deviceButton = ConsoleButton(title: "测试连接", target: nil, action: nil)
    private let verifyLarkButton = ConsoleButton(title: "验证配置", target: nil, action: nil)
    private let selectAudioButton = ConsoleButton(title: "选择 MP3", target: nil, action: nil)
    private let resetAudioButton = ConsoleButton(title: "恢复默认", target: nil, action: nil)
    private let advancedButton = ConsoleButton(title: "高级设置", target: nil, action: nil)
    private let clockTab = ConsoleButton(title: "时钟", target: nil, action: nil)
    private let settingsTab = ConsoleButton(title: "配置", target: nil, action: nil)
    private let logsTab = ConsoleButton(title: "日志", target: nil, action: nil)
    private let clockHint = ConsoleButton(title: "前往配置", target: nil, action: nil)
    private let focusSummary = NSTextField(labelWithString: "")
    private let restSummary = NSTextField(labelWithString: "")
    private let appearanceButton = ConsoleButton(title: "跟随系统", target: nil, action: nil)
    private let audioStatusLabel = NSTextField(labelWithString: "当前使用默认提示音")
    private let environmentStatus = NSTextField(labelWithString: "等待检查")
    private let readinessCount = NSTextField(labelWithString: "0 / 4")
    private let focusModeButton = ConsoleButton(title: "专注 45 分钟", target: nil, action: nil)
    private let restModeButton = ConsoleButton(title: "休息 5 分钟", target: nil, action: nil)
    private let busyIndicator = NSProgressIndicator()
    private let operationIcon = NSImageView()
    private let dial = FocusDialView()
    private let rhythmStrip = RhythmStripView()
    private var appearanceObserver: NSKeyValueObservation?
    private var accessibilityObserver: NSObjectProtocol?
    private var advancedSection: NSBox?
    private var settingsScroll: NSScrollView!
    private var logsPanel: NSBox!
    private var emptyLogLabel: NSTextField!
    private var rootView: NSView!
    private var clockPage: NSView!
    private var settingsPage: NSView!
    private var navigation: FloatingNavigationView!
    private let woodBackground = WoodBackgroundView()
    private var materialCards: [NSBox] = []
    private var settingsCards: [NSBox] = []
    private var inputFields: [NSTextField] = []
    private var readinessLabels: [NSTextField] = []
    private var readinessIcons: [NSImageView] = []
    private var readinessCards: [NSBox] = []
    private var isPreview: Bool { CommandLine.arguments.contains("--ui-preview") }

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate; app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        restoreAppearance()
        buildMenus()
        model.onChange = { [weak self] in self?.refresh() }
        model.onEnvironmentInstallOffer = { [weak self] packages, message in self?.offerEnvironmentInstall(packages: packages, reason: message) }
        buildWindow()
        if isPreview {
            model.deviceIP = "192.168.1.131"; model.hostIP = "192.168.1.198"
            model.focusMinutes = "30"; model.restMinutes = "5"; model.appID = "cli_example_app"
            if !CommandLine.arguments.contains("--preview-empty") {
                model.isAuthorized = true; model.isLarkVerified = true
                model.isEnvironmentReady = true; model.isDeviceReachable = true
                model.status = "配置已就绪，开始你的下一段专注。"
                model.logText = "启动检查：正在验证运行环境。\n✓ 运行环境检查通过\n✓ TC002 自动连接检查通过\n✓ Lark 系统状态验证通过\n配置已就绪，可以启动专注时钟。"
            } else {
                model.deviceIP = ""; model.hostIP = ""; model.appID = ""
                model.status = "填写连接信息，开始配置你的时钟。"
            }
        } else { model.load() }
        populateFieldsFromModel(); refresh()
        if !isPreview { model.autoValidateSavedConfiguration() }
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in self?.refresh() }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshDynamicAppearance()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        if !isPreview { collectFields(); model.save(); model.stopADBServer() }
    }

    private func buildMenus() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu(title: "TC002 专注助手")
        appMenu.addItem(withTitle: "退出 TC002 专注助手", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; menu.addItem(appItem)
        let editItem = NSMenuItem(); let editMenu = NSMenu(title: "编辑")
        for (title, action, key) in [("撤销", Selector(("undo:")), "z"), ("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        editItem.submenu = editMenu; menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    private func buildWindow() {
        let root = NSView(); root.wantsLayer = true; rootView = root
        woodBackground.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(woodBackground); pin(woodBackground, to: root, inset: 0)
        let clock = buildClockPage(); clockPage = clock
        let settings = buildSettingsPage(); settingsPage = settings; settings.isHidden = true
        let logs = buildLogPanel(); logsPanel = logs; logs.isHidden = true
        let glass = buildNavigation()
        for view in [clock, settings, logs, glass] {
            view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view)
        }
        for page in [clock, settings, logs] {
            NSLayoutConstraint.activate([
                page.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
                page.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),
                page.topAnchor.constraint(equalTo: root.topAnchor, constant: 44),
                page.bottomAnchor.constraint(equalTo: glass.topAnchor, constant: -24)
            ])
        }
        NSLayoutConstraint.activate([
            glass.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            glass.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -28),
            glass.widthAnchor.constraint(equalToConstant: 348),
            glass.heightAnchor.constraint(equalToConstant: 64)
        ])
        let compact = isPreview && CommandLine.arguments.contains("--preview-compact")
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: compact ? 760 : 800, height: compact ? 720 : 780), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = isPreview ? "TC002 · 设计预览" : "TC002 专注助手"
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 760, height: 720)
        window.contentView = root; window.center(); window.makeKeyAndOrderFront(nil)
        refreshDynamicAppearance(); NSApp.activate(ignoringOtherApps: true)
    }

    private func buildClockPage() -> NSView {
        let page = NSView()
        dial.toolTip = "拖动圆环：顺时针增加，逆时针减少。1–240 分钟；修改后下次启动生效。"
        dial.onMinutesChanged = { [weak self] minutes in
            guard let self else { return }
            if self.dial.mode == .focus {
                self.focusField.stringValue = String(minutes); self.model.focusMinutes = String(minutes)
            } else {
                self.restField.stringValue = String(minutes); self.model.restMinutes = String(minutes)
            }
            self.updateRhythmPreview()
        }
        dial.onEditingEnded = { [weak self] in
            guard let self, !self.isPreview else { return }
            self.collectFields(); self.model.save()
        }
        prepareButton(focusModeButton, symbol: nil, action: #selector(selectFocusDial), style: .selectedTab)
        prepareButton(restModeButton, symbol: nil, action: #selector(selectRestDial), style: .quiet)
        focusModeButton.cornerRadius = 16; restModeButton.cornerRadius = 16
        focusModeButton.foregroundColor = FocusPalette.clockBronze
        restModeButton.foregroundColor = FocusPalette.clockRest
        focusModeButton.font = .systemFont(ofSize: 12, weight: .semibold)
        restModeButton.font = .systemFont(ofSize: 12, weight: .semibold)
        let duration = horizontal([focusModeButton, restModeButton], spacing: 4)
        duration.distribution = .fillEqually
        focusModeButton.toolTip = "旋转圆环调整专注分钟数"
        restModeButton.toolTip = "旋转圆环调整休息分钟数"
        for label in [focusSummary, restSummary] {
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = label === focusSummary ? FocusPalette.clockBronze : FocusPalette.clockRest
        }
        let legend = horizontal([focusSummary, NSView(), restSummary], spacing: 12)
        let rhythm = vertical([rhythmStrip, legend], spacing: 12)
        rhythmStrip.heightAnchor.constraint(equalToConstant: 8).isActive = true
        prepareButton(startButton, symbol: "play.fill", action: #selector(startFocus), style: .primary)
        startButton.keyEquivalent = "\r"
        startButton.font = .systemFont(ofSize: 13, weight: .semibold)
        startButton.toolTip = "验证配置，启动电脑助手并部署 TC002 临时界面"
        prepareButton(clockHint, symbol: nil, action: #selector(showSettings), style: .quiet)
        clockHint.font = .systemFont(ofSize: 12)
        clockHint.foregroundColor = FocusPalette.clockInk
        let stack = NSStackView(views: [dial, duration, rhythm, startButton, clockHint])
        stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 18
        stack.setCustomSpacing(24, after: duration)
        stack.setCustomSpacing(28, after: rhythm)
        stack.setCustomSpacing(4, after: startButton)
        stack.translatesAutoresizingMaskIntoConstraints = false; page.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: page.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: page.centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: page.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: page.bottomAnchor, constant: -8),
            dial.widthAnchor.constraint(equalToConstant: 320),
            dial.heightAnchor.constraint(equalToConstant: 320),
            duration.widthAnchor.constraint(equalToConstant: 272),
            rhythm.widthAnchor.constraint(equalToConstant: 400),
            startButton.widthAnchor.constraint(equalToConstant: 200)
        ])
        return page
    }

    private func buildSettingsPage() -> NSView {
        let page = NSView()
        prepareButton(appearanceButton, symbol: "circle.lefthalf.filled", action: #selector(showAppearanceMenu), style: .quiet)
        appearanceButton.widthAnchor.constraint(equalToConstant: 112).isActive = true
        appearanceButton.toolTip = "外观：跟随系统 / 浅色 / 深色"
        updateAppearanceButton()
        advancedButton.title = ""
        prepareButton(advancedButton, symbol: "gearshape", action: #selector(toggleAdvanced), style: .quiet)
        advancedButton.widthAnchor.constraint(equalToConstant: 32).isActive = true
        advancedButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        advancedButton.setAccessibilityLabel("展开高级设置")
        advancedButton.toolTip = "高级设置：使用自定义源码目录时才需要修改"
        let header = horizontal([text("配置", size: 22, weight: .semibold), NSView(), advancedButton, appearanceButton], spacing: 12)
        let overview = buildReadiness()
        let scroll = buildSettings(); settingsScroll = scroll
        let operation = buildOperationBar()
        for view in [header, overview, scroll, operation] {
            view.translatesAutoresizingMaskIntoConstraints = false; page.addSubview(view)
            view.leadingAnchor.constraint(equalTo: page.leadingAnchor).isActive = true
            view.trailingAnchor.constraint(equalTo: page.trailingAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: page.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 36),
            overview.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            scroll.topAnchor.constraint(equalTo: overview.bottomAnchor, constant: 16),
            scroll.bottomAnchor.constraint(equalTo: operation.topAnchor, constant: -12),
            operation.bottomAnchor.constraint(equalTo: page.bottomAnchor),
            operation.heightAnchor.constraint(equalToConstant: 54)
        ])
        return page
    }

    private func buildNavigation() -> NSView {
        prepareButton(clockTab, symbol: "timer", action: #selector(showClock), style: .selectedTab, height: 44)
        prepareButton(settingsTab, symbol: "slider.horizontal.3", action: #selector(showSettings), style: .tab, height: 44)
        prepareButton(logsTab, symbol: "text.alignleft", action: #selector(showLogs), style: .tab, height: 44)
        let row = horizontal([clockTab, settingsTab, logsTab], spacing: 4)
        row.distribution = .fillEqually
        for (index, button) in [clockTab, settingsTab, logsTab].enumerated() {
            button.font = .systemFont(ofSize: 12, weight: .semibold); button.cornerRadius = 22
            button.isNavigationItem = true
            button.setAccessibilityValue(index == 0 ? "已选中" : "未选中")
        }
        let glass = FloatingNavigationView(content: row, buttons: [clockTab, settingsTab, logsTab], forceCompatibility: isPreview && CommandLine.arguments.contains("--preview-legacy-glass"))
        glass.onSelection = { [weak self] index in self?.selectPage(index) }
        navigation = glass
        return glass
    }

    private func buildReadiness() -> NSView {
        readinessCount.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        readinessCount.textColor = FocusPalette.muted
        let heading = horizontal([text("系统状态", size: 11, weight: .semibold), NSView(), readinessCount], spacing: 8)
        let chips = [readinessChip("运行环境", symbol: "checkmark.shield"), readinessChip("Lark 授权", symbol: "person.crop.circle"), readinessChip("时钟连接", symbol: "display"), readinessChip("电脑助手", symbol: "bolt")]
        let top = horizontal([chips[0], chips[1]], spacing: 8); top.distribution = .fillEqually
        let bottom = horizontal([chips[2], chips[3]], spacing: 8); bottom.distribution = .fillEqually
        let stack = vertical([heading, top, bottom], spacing: 8)
        for view in [heading, top, bottom] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        top.heightAnchor.constraint(equalToConstant: 40).isActive = true
        bottom.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return stack
    }

    private func readinessChip(_ title: String, symbol name: String) -> NSBox {
        let box = card(radius: 9)
        let icon = NSImageView(image: symbol(name, size: 12, weight: .medium))
        icon.widthAnchor.constraint(equalToConstant: 15).isActive = true
        let label = text(title, size: 12, weight: .medium, color: FocusPalette.muted)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = horizontal([icon, label], spacing: 6)
        row.translatesAutoresizingMaskIntoConstraints = false; box.contentView!.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor, constant: 9),
            row.trailingAnchor.constraint(lessThanOrEqualTo: box.contentView!.trailingAnchor, constant: -6),
            row.centerYAnchor.constraint(equalTo: box.contentView!.centerYAnchor)
        ])
        readinessCards.append(box); readinessIcons.append(icon); readinessLabels.append(label)
        return box
    }

    private func buildSettings() -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.verticalScroller = KnobOnlyScroller()
        scroll.scrollerStyle = .overlay
        let document = FlippedContentView(); document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        let stack = vertical([], spacing: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(stack)
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -16)
        ])
        let device = buildDeviceCard(); let environment = buildEnvironmentCard()
        let top = horizontal([device, environment], spacing: 12)
        top.alignment = .top
        stack.addArrangedSubview(top)
        top.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        device.widthAnchor.constraint(equalTo: top.widthAnchor, multiplier: 0.63, constant: -6).isActive = true
        environment.widthAnchor.constraint(equalTo: top.widthAnchor, multiplier: 0.37, constant: -6).isActive = true
        for card in [buildLarkCard(), buildRhythmCard()] {
            stack.addArrangedSubview(card); card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        prepareButton(stopButton, symbol: "stop", action: #selector(stopServices), style: .quiet)
        prepareButton(rebootButton, symbol: "arrow.counterclockwise", action: #selector(reboot), style: .quiet)
        stopButton.toolTip = "停止 Mac 上的 EMQX、Lark bridge 和 MQTT adapter"
        rebootButton.toolTip = "重启 TC002，恢复设备原生界面"
        let serviceActions = horizontal([text("临时部署 · 保留原生固件", size: 11, color: FocusPalette.muted), NSView(), stopButton, rebootButton], spacing: 8)
        stack.addArrangedSubview(serviceActions)
        serviceActions.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        configureField(repoField, placeholder: "自动使用 App 内置资源")
        let advanced = panel("项目目录", detail: "通常无需修改", symbol: "folder", body: repoField, height: 100)
        advanced.isHidden = true; advancedSection = advanced
        stack.addArrangedSubview(advanced); advanced.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return scroll
    }

    private func buildDeviceCard() -> NSBox {
        configureField(deviceField, placeholder: "192.168.1.131")
        configureField(hostField, placeholder: "自动识别局域网 IP")
        prepareButton(deviceButton, symbol: nil, action: #selector(checkDevice))
        deviceButton.widthAnchor.constraint(equalToConstant: 80).isActive = true
        let detect = ConsoleButton(title: "自动识别", target: nil, action: nil)
        prepareButton(detect, symbol: nil, action: #selector(detectHost))
        detect.widthAnchor.constraint(equalToConstant: 80).isActive = true
        let deviceRow = horizontal([deviceField, deviceButton], spacing: 8)
        let hostRow = horizontal([hostField, detect], spacing: 8)
        deviceField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hostField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let body = vertical([fieldGroup("时钟 IP", content: deviceRow), fieldGroup("电脑 IP", content: hostRow)], spacing: 9)
        return panel("连接时钟", detail: "", symbol: "display", body: body, height: 166)
    }

    private func buildEnvironmentCard() -> NSBox {
        let description = text("运行组件与设备资源\n打开时自动检查。", size: 12, color: FocusPalette.muted)
        description.usesSingleLineMode = false; description.maximumNumberOfLines = 2; description.lineBreakMode = .byWordWrapping
        environmentStatus.font = .systemFont(ofSize: 12, weight: .medium)
        environmentStatus.textColor = FocusPalette.muted
        prepareButton(environmentButton, symbol: "arrow.clockwise", action: #selector(checkEnvironment))
        let body = vertical([description, environmentStatus, environmentButton], spacing: 12)
        environmentButton.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        return panel("运行环境", detail: "", symbol: "checkmark.shield", body: body, height: 166)
    }

    private func buildLarkCard() -> NSBox {
        configureField(appIDField, placeholder: "cli_…")
        configureField(appSecretField, placeholder: "授权后保存在钥匙串")
        let id = fieldGroup("App ID", content: appIDField)
        let secret = fieldGroup("App Secret", content: appSecretField)
        let credentials = horizontal([id, secret], spacing: 12); credentials.distribution = .fillEqually
        prepareButton(authorizeButton, symbol: "arrow.up.forward", action: #selector(authorize))
        prepareButton(verifyLarkButton, symbol: "checkmark", action: #selector(verifyLark), style: .quiet)
        let caption = text("专注时，自动同步 Lark 状态。", size: 12, color: FocusPalette.muted)
        caption.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let actions = horizontal([caption, NSView(), verifyLarkButton, authorizeButton], spacing: 8)
        let body = vertical([credentials, actions], spacing: 10)
        return panel("Lark 状态同步", detail: "", symbol: "person.crop.circle.badge.checkmark", body: body, height: 140)
    }

    private func buildRhythmCard() -> NSBox {
        configureField(focusField, placeholder: "45")
        configureField(restField, placeholder: "5")
        focusField.font = .monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        focusField.widthAnchor.constraint(equalToConstant: 72).isActive = true
        restField.font = .monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        restField.widthAnchor.constraint(equalToConstant: 72).isActive = true
        let focus = horizontal([text("专注", size: 12, weight: .semibold), focusField, text("分钟", size: 12, color: FocusPalette.muted)], spacing: 10)
        let rest = horizontal([text("休息", size: 12, weight: .semibold), restField, text("分钟", size: 12, color: FocusPalette.muted)], spacing: 10)
        let durations = horizontal([focus, NSView(), rest], spacing: 12)
        prepareButton(selectAudioButton, symbol: "music.note", action: #selector(selectAudio))
        prepareButton(resetAudioButton, symbol: nil, action: #selector(resetAudio), style: .quiet)
        audioStatusLabel.font = .systemFont(ofSize: 12); audioStatusLabel.textColor = FocusPalette.muted
        audioStatusLabel.lineBreakMode = .byTruncatingTail
        audioStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let audio = horizontal([audioStatusLabel, NSView(), resetAudioButton, selectAudioButton], spacing: 8)
        let body = vertical([durations, audio], spacing: 12)
        return panel("时长与提示音", detail: "也可以在时钟页旋转调节", symbol: "music.note", body: body, height: 124)
    }

    private func buildLogPanel() -> NSBox {
        let box = plainRegion()
        let clear = ConsoleButton(title: "清空", target: nil, action: nil)
        prepareButton(clear, symbol: "trash", action: #selector(clearLog), style: .quiet)
        let heading = vertical([text("运行日志", size: 22, weight: .semibold), text("连接、授权和启动进度都会显示在这里。", size: 12, color: FocusPalette.muted)], spacing: 6)
        let header = horizontal([heading, NSView(), clear], spacing: 10)
        logView.isEditable = false; logView.isRichText = false; logView.isSelectable = true
        logView.drawsBackground = false
        logView.isVerticallyResizable = true; logView.isHorizontallyResizable = false
        logView.autoresizingMask = [.width]
        logView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        logView.minSize = .zero
        logView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        logView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        logView.textContainerInset = NSSize(width: 16, height: 16)
        logView.textContainer?.lineFragmentPadding = 0
        logView.textContainer?.widthTracksTextView = true
        logView.textContainer?.containerSize = NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.verticalScroller = KnobOnlyScroller()
        scroll.scrollerStyle = .overlay
        scroll.documentView = logView; scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 10; scroll.layer?.masksToBounds = true
        let footer = text("凭据保存在钥匙串，不显示在日志中。", size: 12, color: FocusPalette.muted)
        let inner = vertical([header, scroll, footer], spacing: 14)
        inner.translatesAutoresizingMaskIntoConstraints = false; box.contentView!.addSubview(inner)
        pin(inner, to: box.contentView!, inset: 0)
        header.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
        scroll.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        emptyLogLabel = text("还没有运行记录\n完成配置后，切换到时钟页开始专注。", size: 13, color: FocusPalette.faint)
        emptyLogLabel.usesSingleLineMode = false; emptyLogLabel.maximumNumberOfLines = 2; emptyLogLabel.alignment = .center
        emptyLogLabel.translatesAutoresizingMaskIntoConstraints = false; box.contentView!.addSubview(emptyLogLabel)
        emptyLogLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor).isActive = true
        emptyLogLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor).isActive = true
        return box
    }

    private func buildOperationBar() -> NSBox {
        let box = plainRegion()
        addSeparator(to: box, atTop: true)
        operationIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        statusField.font = .systemFont(ofSize: 12, weight: .medium)
        statusField.textColor = FocusPalette.muted
        statusField.maximumNumberOfLines = 2; statusField.lineBreakMode = .byWordWrapping
        statusField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        busyIndicator.style = .spinning; busyIndicator.controlSize = .small; busyIndicator.isDisplayedWhenStopped = false
        let row = horizontal([operationIcon, statusField, NSView(), busyIndicator], spacing: 10)
        row.translatesAutoresizingMaskIntoConstraints = false; box.contentView!.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: box.contentView!.trailingAnchor, constant: -16),
            row.centerYAnchor.constraint(equalTo: box.contentView!.centerYAnchor)
        ])
        return box
    }

    private func card(radius: CGFloat = 16) -> NSBox {
        let box = NSBox(); box.boxType = .custom; box.titlePosition = .noTitle
        box.contentViewMargins = .zero; box.cornerRadius = radius; box.borderWidth = 1
        box.fillColor = FocusPalette.surface; box.borderColor = FocusPalette.border
        materialCards.append(box); return box
    }

    /// A form section is a content region, not another framed surface inside the window.
    private func plainRegion() -> NSBox {
        let box = NSBox(); box.boxType = .custom; box.titlePosition = .noTitle
        box.contentViewMargins = .zero; box.cornerRadius = 0; box.borderWidth = 0
        box.fillColor = .clear; box.borderColor = .clear
        return box
    }

    private func addSeparator(to box: NSBox, atTop: Bool = false) {
        let separator = NSBox(); separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        let parent = box.contentView!
        parent.addSubview(separator)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            atTop ? separator.topAnchor.constraint(equalTo: parent.topAnchor) : separator.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
    }

    private func panel(_ title: String, detail: String, symbol name: String, body: NSView, height: CGFloat) -> NSBox {
        // The user requests a quiet backing for each configuration group, not glass panels.
        let box = card(radius: 14)
        settingsCards.append(box); styleSettingsCard(box)
        let icon = NSImageView(image: symbol(name, size: 14, weight: .medium))
        icon.contentTintColor = FocusPalette.muted; icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        let heading = text(title, size: 14, weight: .semibold)
        heading.setContentCompressionResistancePriority(.required, for: .horizontal)
        let header = horizontal([icon, heading, NSView(), text(detail, size: 11, color: FocusPalette.muted)], spacing: 8)
        let inner = vertical([header, body], spacing: 8)
        inner.translatesAutoresizingMaskIntoConstraints = false; box.contentView!.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor, constant: 14),
            inner.trailingAnchor.constraint(equalTo: box.contentView!.trailingAnchor, constant: -14),
            inner.topAnchor.constraint(equalTo: box.contentView!.topAnchor, constant: 10),
            inner.bottomAnchor.constraint(lessThanOrEqualTo: box.contentView!.bottomAnchor, constant: -8),
            header.widthAnchor.constraint(equalTo: inner.widthAnchor),
            body.widthAnchor.constraint(equalTo: inner.widthAnchor),
            box.heightAnchor.constraint(equalToConstant: height)
        ])
        return box
    }

    private func styleSettingsCard(_ box: NSBox) {
        let opacity: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 0.88
        box.fillColor = FocusPalette.settingsSurface.withAlphaComponent(opacity)
        box.borderColor = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? FocusPalette.clockTick : FocusPalette.settingsBorder
    }

    private func configureField(_ field: NSTextField, placeholder: String, height: CGFloat = 36) {
        field.cell = field is NSSecureTextField ? ConsoleSecureCell(textCell: "") : ConsoleTextCell(textCell: "")
        field.isEditable = true; field.isSelectable = true; field.isBezeled = false; field.isBordered = false
        field.drawsBackground = false; field.focusRingType = .exterior
        field.placeholderString = placeholder; field.font = .systemFont(ofSize: 13)
        field.textColor = FocusPalette.text; field.wantsLayer = true
        field.layer?.cornerRadius = 8; field.layer?.borderWidth = 1
        field.delegate = self
        field.heightAnchor.constraint(equalToConstant: height).isActive = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        inputFields.append(field)
    }

    private func fieldGroup(_ title: String, content: NSView) -> NSStackView {
        let group = vertical([text(title, size: 11, weight: .medium, color: FocusPalette.muted), content], spacing: 5)
        content.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
        return group
    }
    private func text(_ value: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = FocusPalette.text) -> NSTextField {
        let field = NSTextField(labelWithString: value); field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color; field.usesSingleLineMode = true; return field
    }
    private func horizontal(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views); stack.orientation = .horizontal; stack.alignment = .centerY; stack.spacing = spacing
        return stack
    }
    private func vertical(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing
        for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }
    private func pin(_ view: NSView, to parent: NSView, inset: CGFloat) {
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
            view.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
            view.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
            view.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)
        ])
    }
    private func prepareButton(_ button: ConsoleButton, symbol name: String?, action: Selector, style: ConsoleButton.Style = .secondary, height: CGFloat? = nil) {
        button.target = self; button.action = action; button.style = style
        button.isBordered = false; button.setButtonType(.momentaryPushIn)
        button.imagePosition = .imageLeading; button.setAccessibilityLabel(button.title)
        button.font = .systemFont(ofSize: 12, weight: .medium)
        if let name { button.image = symbol(name, size: 13, weight: .medium) }
        button.heightAnchor.constraint(equalToConstant: height ?? (style == .primary ? 44 : 32)).isActive = true
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    private func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        return (NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()).withSymbolConfiguration(configuration) ?? NSImage()
    }

    private func appearancePreference() -> String { UserDefaults.standard.string(forKey: "TC002.appearance") ?? "system" }
    private func selectedAppearance() -> String {
        if isPreview {
            switch NSApp.appearance?.name { case .darkAqua: return "dark"; case .aqua: return "light"; default: return "system" }
        }
        return appearancePreference()
    }
    private func updateAppearanceButton() {
        let preference = selectedAppearance()
        appearanceButton.title = preference == "dark" ? "深色" : (preference == "light" ? "浅色" : "跟随系统")
        appearanceButton.image = symbol(preference == "dark" ? "moon" : (preference == "light" ? "sun.max" : "circle.lefthalf.filled"), size: 13, weight: .medium)
        appearanceButton.setAccessibilityLabel("外观：\(appearanceButton.title)")
    }
    private func restoreAppearance() {
        if isPreview { applyAppearance(CommandLine.arguments.contains("--preview-dark") ? "dark" : "light", persist: false) }
        else { applyAppearance(appearancePreference(), persist: false) }
    }
    private func applyAppearance(_ value: String, persist: Bool) {
        switch value { case "light": NSApp.appearance = NSAppearance(named: .aqua); case "dark": NSApp.appearance = NSAppearance(named: .darkAqua); default: NSApp.appearance = nil }
        if persist && !isPreview { UserDefaults.standard.set(value, forKey: "TC002.appearance") }
        updateAppearanceButton()
        refreshDynamicAppearance()
    }
    private func refreshDynamicAppearance() {
        guard rootView != nil else { return }
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            rootView.layer?.backgroundColor = FocusPalette.background.cgColor
            navigation?.refreshAppearance()
            for box in materialCards where !readinessCards.contains(where: { $0 === box }) {
                box.fillColor = FocusPalette.surface; box.borderColor = FocusPalette.border
            }
            for box in settingsCards { styleSettingsCard(box) }
            for field in inputFields {
                field.layer?.backgroundColor = FocusPalette.inset.cgColor
                field.layer?.borderColor = FocusPalette.border.cgColor
                field.textColor = FocusPalette.text
            }
            focusField.textColor = FocusPalette.accent
            logView.backgroundColor = .clear; logView.textColor = FocusPalette.text
        }
        dial.needsDisplay = true; rhythmStrip.needsDisplay = true
        woodBackground.needsDisplay = true
        settingsScroll.verticalScroller?.needsDisplay = true
        logView.enclosingScrollView?.verticalScroller?.needsDisplay = true
    }
    @objc private func showAppearanceMenu() {
        let menu = NSMenu(title: "外观")
        let preference = selectedAppearance()
        for (index, choice) in [("跟随系统", "system", "circle.lefthalf.filled"), ("浅色", "light", "sun.max"), ("深色", "dark", "moon")].enumerated() {
            let item = NSMenuItem(title: choice.0, action: #selector(selectAppearance(_:)), keyEquivalent: "")
            item.target = self; item.tag = index
            item.image = symbol(choice.2, size: 13, weight: .regular)
            item.state = preference == choice.1 ? .on : .off
            menu.addItem(item)
        }
        let y = appearanceButton.isFlipped ? appearanceButton.bounds.maxY + 4 : appearanceButton.bounds.minY - 4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: appearanceButton)
    }
    @objc private func selectAppearance(_ sender: NSMenuItem) {
        applyAppearance(["system", "light", "dark"][sender.tag], persist: true); refresh()
    }
    private func selectPage(_ page: Int) {
        let tabs = [clockTab, settingsTab, logsTab]
        let navigationHadFocus = tabs.contains { window.firstResponder === $0 }
        window.makeFirstResponder(nil)
        clockPage.isHidden = page != 0; settingsPage.isHidden = page != 1; logsPanel.isHidden = page != 2
        navigation.select(index: page)
        for (index, button) in [clockTab, settingsTab, logsTab].enumerated() {
            button.style = index == page ? .selectedTab : .tab
            button.setAccessibilityValue(index == page ? "已选中" : "未选中")
        }
        startButton.keyEquivalent = page == 0 ? "\r" : ""
        // Ending field editing must not discard focus from the control driving navigation.
        if navigationHadFocus { window.makeFirstResponder(tabs[page]) }
    }
    @objc private func showClock() { selectPage(0) }
    @objc private func showSettings() { selectPage(1) }
    @objc private func showLogs() { selectPage(2) }

    private func collectFields() {
        model.deviceIP = deviceField.stringValue; model.hostIP = hostField.stringValue
        model.focusMinutes = focusField.stringValue; model.restMinutes = restField.stringValue
        model.appID = appIDField.stringValue; model.appSecret = appSecretField.stringValue; model.repoPath = repoField.stringValue
    }
    private func populateFieldsFromModel() {
        deviceField.stringValue = model.deviceIP; hostField.stringValue = model.hostIP
        focusField.stringValue = model.focusMinutes; restField.stringValue = model.restMinutes
        appIDField.stringValue = model.appID; repoField.stringValue = model.repoPath
    }
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === focusField || field === restField else { return }
        updateRhythmPreview()
    }
    private func updateRhythmPreview() {
        let focus = min(240, max(1, Int(focusField.stringValue) ?? 45))
        let rest = min(240, max(1, Int(restField.stringValue) ?? 5))
        dial.focusMinutes = focus; dial.restMinutes = rest
        rhythmStrip.focusMinutes = focus; rhythmStrip.restMinutes = rest
        focusSummary.stringValue = "专注 · \(focus) 分钟"; restSummary.stringValue = "休息 · \(rest) 分钟"
        focusModeButton.title = "专注 \(focus) 分钟"; restModeButton.title = "休息 \(rest) 分钟"
        for button in [focusModeButton, restModeButton] {
            button.setAccessibilityLabel(button.title); button.invalidateIntrinsicContentSize(); button.needsDisplay = true
        }
        focusModeButton.style = dial.mode == .focus ? .selectedTab : .quiet
        restModeButton.style = dial.mode == .rest ? .selectedTab : .quiet
        focusModeButton.setAccessibilityValue(dial.mode == .focus ? "已选中" : "未选中")
        restModeButton.setAccessibilityValue(dial.mode == .rest ? "已选中" : "未选中")
        dial.updateAccessibility()
    }
    @objc private func selectFocusDial() { dial.mode = .focus; updateRhythmPreview() }
    @objc private func selectRestDial() { dial.mode = .rest; updateRhythmPreview() }
    private func updateReadiness(_ index: Int, title: String, ready: Bool, partial: Bool = false) {
        let color = ready ? FocusPalette.ready : (partial ? FocusPalette.warning : FocusPalette.faint)
        readinessLabels[index].stringValue = title
        readinessLabels[index].textColor = ready || partial ? color : FocusPalette.muted
        readinessIcons[index].contentTintColor = color
        readinessIcons[index].image = symbol(ready ? "checkmark.circle.fill" : (partial ? "circle.lefthalf.filled" : "circle"), size: 12, weight: .medium)
        readinessCards[index].fillColor = ready ? FocusPalette.readySoft : FocusPalette.surface.withAlphaComponent(0.45)
        readinessCards[index].borderColor = ready ? FocusPalette.ready.withAlphaComponent(0.15) : FocusPalette.border
    }
    private func refresh() {
        DispatchQueue.main.async { [self] in
            statusField.stringValue = model.status
            let logChanged = logView.string != model.logText
            if logChanged {
                logView.string = model.logText
                let style = NSMutableParagraphStyle(); style.lineSpacing = 5; style.paragraphSpacing = 4
                logView.textStorage?.setAttributes([.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: FocusPalette.text, .paragraphStyle: style], range: NSRange(location: 0, length: logView.string.utf16.count))
                logView.scrollToEndOfDocument(nil)
            }
            emptyLogLabel.isHidden = !model.logText.isEmpty
            refreshDynamicAppearance(); updateRhythmPreview()
            dial.isEnabled = !model.isBusy
            focusModeButton.isEnabled = !model.isBusy; restModeButton.isEnabled = !model.isBusy
            updateReadiness(0, title: model.isEnvironmentReady ? "环境就绪" : "待检查环境", ready: model.isEnvironmentReady)
            updateReadiness(1, title: model.isLarkVerified ? "Lark 就绪" : (model.isAuthorized ? "Lark 待验证" : "待授权 Lark"), ready: model.isLarkVerified, partial: model.isAuthorized)
            updateReadiness(2, title: model.isDeviceReachable ? "时钟已连接" : "待连接时钟", ready: model.isDeviceReachable)
            let servicesReady = model.areServicesRunning || model.isReadyToStart
            updateReadiness(3, title: model.areServicesRunning ? "助手运行中" : (model.isReadyToStart ? "可以启动" : (model.areServicesInstalled ? "助手已停止" : "待首次启动")), ready: servicesReady, partial: model.areServicesInstalled)
            let count = [model.isEnvironmentReady, model.isLarkVerified, model.isDeviceReachable, servicesReady].filter { $0 }.count
            readinessCount.stringValue = "\(count) / 4"; readinessCount.textColor = count == 4 ? FocusPalette.ready : FocusPalette.muted
            clockHint.title = model.isBusy ? "正在处理 · 点击查看进度" : (model.areServicesRunning ? "助手运行中 · 查看配置" : (count == 4 ? "配置已就绪 · 查看配置" : "完成配置后开始 · 前往配置"))
            clockHint.setAccessibilityLabel(clockHint.title); clockHint.invalidateIntrinsicContentSize()
            startButton.title = model.isBusy ? "正在处理…" : (model.areServicesRunning ? "重新启动专注" : "启动专注时钟")
            startButton.setAccessibilityLabel(startButton.title)
            environmentStatus.stringValue = model.isEnvironmentReady ? "✓ 所有运行组件已就绪" : "等待检查运行组件"
            environmentStatus.textColor = model.isEnvironmentReady ? FocusPalette.ready : FocusPalette.muted
            let hasError = model.status.contains("失败") || model.status.contains("未通过") || model.status.contains("未完成")
            operationIcon.image = symbol(model.isBusy ? "arrow.trianglehead.2.clockwise.rotate.90" : (hasError ? "exclamationmark.circle" : "circle.dotted.circle"), size: 17, weight: .medium)
            operationIcon.contentTintColor = hasError ? FocusPalette.warning : FocusPalette.accent
            if model.isBusy { busyIndicator.startAnimation(nil) } else { busyIndicator.stopAnimation(nil) }
            authorizeButton.title = model.isOAuthRunning ? "重新开始授权" : (model.isAuthorized ? "重新授权" : "授权 Lark")
            authorizeButton.setAccessibilityLabel(authorizeButton.title)
            authorizeButton.invalidateIntrinsicContentSize()
            audioStatusLabel.stringValue = isPreview ? "当前使用默认提示音" : model.customAudioStatus
            authorizeButton.isEnabled = !model.isBusy || model.isOAuthRunning
            environmentButton.isEnabled = !model.isBusy; deviceButton.isEnabled = !model.isBusy
            verifyLarkButton.isEnabled = !model.isBusy && model.isAuthorized
            selectAudioButton.isEnabled = !model.isBusy; resetAudioButton.isEnabled = !model.isBusy && model.hasCustomAudio
            startButton.isEnabled = !model.isBusy && model.isAuthorized
            stopButton.isEnabled = !model.isBusy && model.areServicesRunning
            rebootButton.isEnabled = !model.isBusy
            if model.appSecret.isEmpty && model.isAuthorized && !model.isBusy { appSecretField.stringValue = "" }
        }
    }

    @objc private func detectHost() { guard !isPreview else { return }; collectFields(); model.detectHost(); hostField.stringValue = model.hostIP }
    @objc private func checkEnvironment() { guard !isPreview else { return }; collectFields(); model.checkEnvironment() }
    @objc private func checkDevice() { guard !isPreview else { return }; collectFields(); model.checkDevice() }
    @objc private func verifyLark() { guard !isPreview else { return }; collectFields(); model.verifyLark() }
    @objc private func authorize() { guard !isPreview else { return }; collectFields(); model.authorizeLark() }
    @objc private func selectAudio() {
        guard !isPreview && !model.isBusy else { return }
        let panel = NSOpenPanel(); panel.title = "选择提示音"; panel.prompt = "使用此 MP3"
        panel.allowedContentTypes = [.mp3]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { model.chooseCustomAudio(url) }
    }
    @objc private func resetAudio() { guard !isPreview else { return }; model.resetCustomAudio() }
    @objc private func toggleAdvanced() {
        guard let advancedSection else { return }; advancedSection.isHidden.toggle()
        advancedButton.setAccessibilityLabel(advancedSection.isHidden ? "展开高级设置" : "收起高级设置")
        advancedButton.style = advancedSection.isHidden ? .quiet : .selectedTab
    }
    @objc private func startFocus() { guard !isPreview else { return }; collectFields(); model.startFocus() }
    @objc private func stopServices() { guard !isPreview else { return }; model.stopComputerServices() }
    @objc private func clearLog() { model.logText = ""; refresh() }
    @objc private func reboot() {
        guard !isPreview else { return }
        let alert = NSAlert(); alert.messageText = "确认重启时钟？"
        alert.informativeText = "重启会结束临时专注界面，恢复设备原生界面。固件不会被修改。"
        alert.addButton(withTitle: "重启"); alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn { collectFields(); model.rebootDevice() }
    }
    private func offerEnvironmentInstall(packages: [String], reason: String) {
        let names = packages.map { $0 == "node" ? "Node.js 24+" : ($0 == "android-platform-tools" ? "ADB" : $0.uppercased()) }
        let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = "缺少运行组件"
        alert.informativeText = "\(reason)\n\n是否使用 Homebrew 安装：\(names.joined(separator: "、"))？"
        alert.addButton(withTitle: "安装"); alert.addButton(withTitle: "暂不安装")
        if alert.runModal() == .alertFirstButtonReturn { model.installEnvironment(packages: packages) }
    }
}
